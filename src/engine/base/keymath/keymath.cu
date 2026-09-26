// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "keymath.h"

#include <stdlib.h>
#include <string.h>

#include <utility>
#include <vector>

#define KEYMATH_HELD(held_, evacaddr_, error_, kind_) \
    engine_error_check((held_), (kind_), ENGINE_MODULE_KEYMATH, (unsigned int)__LINE__, (const void *)(evacaddr_), \
                       (error_))

typedef std::vector<unsigned int> ExactLimbs;

struct ImprintTerm
{
    unsigned int negative;
    unsigned long long shift;
    std::vector<ExactLimbs> rows[ENGINE_AXES];
};

static ExactLimbs exact_sum(const ExactLimbs &left, const ExactLimbs &right)
{
    const size_t wider = (left.size() > right.size()) ? left.size() : right.size();
    ExactLimbs sum(wider + 1u, 0u);
    unsigned long long carry = 0ull;
    for (size_t limb = 0u; limb < wider; limb += 1u)
    {
        const unsigned long long total = carry + ((limb < left.size()) ? left[limb] : 0u)
                                       + ((limb < right.size()) ? right[limb] : 0u);
        sum[limb] = (unsigned int)(total & 0xFFFFFFFFull);
        carry = total >> 32u;
    }
    sum[wider] = (unsigned int)carry;
    while ((sum.size() > 1u) && (sum.back() == 0u))
    {
        sum.pop_back();
    }
    return sum;
}

static unsigned long long exact_bit_length(const ExactLimbs &value)
{
    for (size_t limb = value.size(); limb > 0u; limb -= 1u)
    {
        unsigned int top = value[limb - 1u];
        if (top != 0u)
        {
            unsigned long long bits = (unsigned long long)(limb - 1u) * 32ull;
            while (top != 0u)
            {
                bits += 1ull;
                top >>= 1u;
            }
            return bits;
        }
    }
    return 0ull;
}

static ExactLimbs exact_less_one(ExactLimbs value)
{
    for (size_t limb = 0u; limb < value.size(); limb += 1u)
    {
        const unsigned int was = value[limb];
        value[limb] = was - 1u;
        if (was != 0u)
        {
            break;
        }
    }
    return value;
}

static void imprint_unit_step(std::vector<ExactLimbs> &row)
{
    const ExactLimbs zero(1u, 0u);
    std::vector<ExactLimbs> stepped(row.size() + 1u);
    for (size_t tap = 0u; tap < stepped.size(); tap += 1u)
    {
        const ExactLimbs &here = (tap < row.size()) ? row[tap] : zero;
        const ExactLimbs &before = (tap > 0u) ? row[tap - 1u] : zero;
        stepped[tap] = exact_sum(here, before);
    }
    row.swap(stepped);
}

extern "C" long keymath_imprint(const KeymathImprintRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return KEYMATH_REFUSED;
    }
    EngineError *const error = request->error;
    if (!KEYMATH_HELD((request->key != NULL) && (request->steps != NULL) && (request->count != 0u), request, error,
                      ENGINE_ERROR_REQUEST))
    {
        return KEYMATH_REFUSED;
    }
    memset(request->key, 0, sizeof(*request->key));

    std::vector<ImprintTerm> running(1u);
    running[0].negative = 0u;
    running[0].shift = 0ull;
    for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
    {
        running[0].rows[axis].assign(1u, ExactLimbs(1u, 1u));
    }
    std::vector<ImprintTerm> kept;
    int have_kept = 0;
    // whether the running terms' and the kept terms' centres sit half a voxel before the voxel on each axis: an order
    // o's window starts floor((o + 1) / 2) before it, and the centre moves half a voxel with each odd order
    unsigned int running_half[ENGINE_AXES] = {0u, 0u, 0u};
    unsigned int kept_half[ENGINE_AXES] = {0u, 0u, 0u};
    for (unsigned int step = 0u; step < request->count; step += 1u)
    {
        const EngineStep &doing = request->steps[step];
        if (doing.operation == ENGINE_SMOOTH)
        {
            for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
            {
                running_half[axis] ^= doing.orders[axis] & 1u;
                for (ImprintTerm &term : running)
                {
                    for (unsigned int unit = 0u; unit < doing.orders[axis]; unit += 1u)
                    {
                        imprint_unit_step(term.rows[axis]);
                    }
                }
            }
        }
        else if (doing.operation == ENGINE_KEEP)
        {
            kept = running;
            have_kept = 1;
            memcpy(kept_half, running_half, sizeof(kept_half));
        }
        else if ((doing.operation == ENGINE_SCALE_SUBTRACT) && (have_kept != 0))
        {
            // terms subtracted half a voxel apart are no residual of one voxel
            if (!KEYMATH_HELD(memcmp(kept_half, running_half, sizeof(kept_half)) == 0, &doing, error,
                              ENGINE_ERROR_REQUEST))
            {
                return KEYMATH_REFUSED;
            }
            std::vector<ImprintTerm> next = kept;
            for (ImprintTerm &term : next)
            {
                term.shift += (unsigned long long)doing.shift;
            }
            for (ImprintTerm term : running)
            {
                term.negative ^= 1u;
                next.push_back(term);
            }
            running.swap(next);
        }
        else
        {
            KEYMATH_HELD(0, &doing, error, ENGINE_ERROR_REQUEST);
            return KEYMATH_REFUSED;
        }
    }

    std::vector<EngineKeyTerm> table(running.size());
    std::vector<unsigned int> limbs;
    for (size_t index = 0u; index < running.size(); index += 1u)
    {
        const ImprintTerm &term = running[index];
        EngineKeyTerm &out = table[index];
        memset(&out, 0, sizeof(out));
        out.negative = term.negative;
        out.shift = term.shift;
        for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
        {
            const std::vector<ExactLimbs> &row = term.rows[axis];
            size_t widest = 1u;
            ExactLimbs sum(1u, 0u);
            for (const ExactLimbs &weight : row)
            {
                widest = (weight.size() > widest) ? weight.size() : widest;
                sum = exact_sum(sum, weight);
            }
            EngineKeyRow &placed = out.row[axis];
            placed.taps = (unsigned long long)row.size();
            placed.limbs = (unsigned long long)widest;
            placed.first = (unsigned long long)limbs.size();
            placed.growth_bits = exact_bit_length(exact_less_one(sum));
            for (size_t limb = 0u; limb < widest; limb += 1u)
            {
                for (const ExactLimbs &weight : row)
                {
                    limbs.push_back((limb < weight.size()) ? weight[limb] : 0u);
                }
            }
        }
    }
    EngineKey *const key = request->key;
    key->term = (EngineKeyTerm *)malloc((table.size() + 1u) * sizeof(EngineKeyTerm));
    key->limbs = (unsigned int *)malloc((limbs.size() + 1u) * sizeof(unsigned int));
    if (!KEYMATH_HELD((key->term != NULL) && (key->limbs != NULL), key, error, ENGINE_ERROR_RESOURCE))
    {
        keymath_key_release(key);
        return KEYMATH_REFUSED;
    }
    memcpy(key->term, table.data(), table.size() * sizeof(EngineKeyTerm));
    memcpy(key->limbs, limbs.data(), limbs.size() * sizeof(unsigned int));
    key->terms = (unsigned int)table.size();
    key->limb_count = (unsigned long long)limbs.size();
    return (long)key->terms;
}

extern "C" void keymath_key_release(EngineKey *key)
{
    free(key->term);
    free(key->limbs);
    memset(key, 0, sizeof(*key));
}

static unsigned int keymath_word_bits(unsigned long long value)
{
    unsigned int bits = 0u;
    while (value != 0ull)
    {
        bits += 1u;
        value >>= 1u;
    }
    return bits;
}

static int keymath_record_reads(EngineRecordOperation operation)
{
    return (operation == ENGINE_RECORD_PRODUCT) || (operation == ENGINE_RECORD_SUM)
        || (operation == ENGINE_RECORD_DIFFERENCE) || (operation == ENGINE_RECORD_LADDER)
        || (operation == ENGINE_RECORD_ABSOLUTE) || (operation == ENGINE_RECORD_COMPARE)
        || (operation == ENGINE_RECORD_QUOTIENT) || (operation == ENGINE_RECORD_REMAINDER)
        || (operation == ENGINE_RECORD_GCD) || (operation == ENGINE_RECORD_EXACT_QUOTIENT)
        || (operation == ENGINE_RECORD_XOR) || (operation == ENGINE_RECORD_AND);
}

// whether a step's register is never negative, read from its operation and its operands': a field read unsigned, a
// constant, an absolute value, a gcd and a table's entry are never negative; so are a sum, product, quotient, exact
// quotient or xor of two such, a remainder of one such (it carries the numerator's sign), an and with one such, and a
// wrap that passes one such through unchanged
static char keymath_never_negative(const EngineRecordStep &doing, const std::vector<char> &never_negative,
                                   int wrap_passes)
{
    const EngineRecordOperation operation = doing.operation;
    if ((operation == ENGINE_RECORD_FIELD) || (operation == ENGINE_RECORD_CONSTANT)
        || (operation == ENGINE_RECORD_ABSOLUTE) || (operation == ENGINE_RECORD_GCD)
        || (operation == ENGINE_RECORD_TABLE))
    {
        return 1;
    }
    if ((operation == ENGINE_RECORD_SUM) || (operation == ENGINE_RECORD_PRODUCT)
        || (operation == ENGINE_RECORD_QUOTIENT) || (operation == ENGINE_RECORD_EXACT_QUOTIENT)
        || (operation == ENGINE_RECORD_XOR))
    {
        return ((never_negative[doing.left] != 0) && (never_negative[doing.right] != 0)) ? 1 : 0;
    }
    if (operation == ENGINE_RECORD_REMAINDER)
    {
        return never_negative[doing.left];
    }
    if (operation == ENGINE_RECORD_AND)
    {
        return ((never_negative[doing.left] != 0) || (never_negative[doing.right] != 0)) ? 1 : 0;
    }
    if (operation == ENGINE_RECORD_WRAP)
    {
        return ((wrap_passes != 0) && (never_negative[doing.left] != 0)) ? 1 : 0;
    }
    return 0;
}

// a coefficient or constant of a linear form stays within this, so a sum of two and the product by a constant are
// checked in one word
#define KEYMATH_COEFFICIENT_MOST (1ll << 62)

// a register as a linear form: integer coefficients over atoms, each an earlier register the form does not open (a
// field, or any register no sum, difference or product by a constant made), plus a constant. Every register has one;
// an atom's is itself with coefficient 1. Its width is read from the form (A16, Mathai and Thiang's bulk-boundary
// map read as a restriction on the dual side): |x| <= |c| + sum |c_i| (2^(b_i) - 1) over the atoms' widths b_i
struct KeymathForm
{
    long long constant;
    std::vector<std::pair<unsigned int, long long>> terms;
};

static KeymathForm keymath_form_atom(unsigned int step)
{
    KeymathForm form;
    form.constant = 0ll;
    form.terms.assign(1u, std::pair<unsigned int, long long>(step, 1ll));
    return form;
}

static long long keymath_magnitude(long long value)
{
    return (value < 0ll) ? -value : value;
}

// left + sign right, the terms merged by atom; 0 where a coefficient or the constant would pass
// KEYMATH_COEFFICIENT_MOST
static int keymath_form_add(const KeymathForm &left, const KeymathForm &right, long long sign, KeymathForm *sum)
{
    sum->constant = left.constant + (sign * right.constant);
    sum->terms.clear();
    int held = keymath_magnitude(sum->constant) <= KEYMATH_COEFFICIENT_MOST;
    size_t at_left = 0u;
    size_t at_right = 0u;
    while (held && ((at_left < left.terms.size()) || (at_right < right.terms.size())))
    {
        const int take_left = (at_right == right.terms.size())
                           || ((at_left < left.terms.size())
                               && (left.terms[at_left].first <= right.terms[at_right].first));
        const int take_right = (at_left == left.terms.size())
                            || ((at_right < right.terms.size())
                                && (right.terms[at_right].first <= left.terms[at_left].first));
        const unsigned int atom = take_left ? left.terms[at_left].first : right.terms[at_right].first;
        const long long coefficient = (take_left ? left.terms[at_left].second : 0ll)
                                    + (take_right ? (sign * right.terms[at_right].second) : 0ll);
        at_left += take_left ? 1u : 0u;
        at_right += take_right ? 1u : 0u;
        held = keymath_magnitude(coefficient) <= KEYMATH_COEFFICIENT_MOST;
        if (held && (coefficient != 0ll))
        {
            sum->terms.push_back(std::pair<unsigned int, long long>(atom, coefficient));
        }
    }
    return held;
}

// the form times a constant; 0 where a coefficient or the constant would pass KEYMATH_COEFFICIENT_MOST
static int keymath_form_scale(const KeymathForm &form, long long factor, KeymathForm *scaled)
{
    const long long most = (factor == 0ll) ? KEYMATH_COEFFICIENT_MOST
                                           : (KEYMATH_COEFFICIENT_MOST / keymath_magnitude(factor));
    int held = keymath_magnitude(form.constant) <= most;
    scaled->constant = held ? (form.constant * factor) : 0ll;
    scaled->terms.clear();
    for (size_t at = 0u; held && (at < form.terms.size()) && (factor != 0ll); at += 1u)
    {
        held = keymath_magnitude(form.terms[at].second) <= most;
        scaled->terms.push_back(
            std::pair<unsigned int, long long>(form.terms[at].first, form.terms[at].second * factor));
    }
    return held;
}

// a magnitude below 2^62 shifted up, as exact limbs
static ExactLimbs keymath_shifted(unsigned long long magnitude, unsigned long long shift)
{
    ExactLimbs value((size_t)(shift / 32ull) + 3u, 0u);
    const unsigned int part = (unsigned int)(shift % 32ull);
    const size_t whole = (size_t)(shift / 32ull);
    // the magnitude is below 2^62, so shifted by fewer than 32 bits it spans at most three limbs
    const unsigned long long low = magnitude << part;
    const unsigned long long high = (part == 0u) ? 0ull : (magnitude >> (64u - part));
    value[whole] = (unsigned int)(low & 0xFFFFFFFFull);
    value[whole + 1u] = (unsigned int)(low >> 32u);
    value[whole + 2u] = (unsigned int)high;
    return value;
}

// the bits a form's value needs: with B = |c| + sum |c_i| 2^(b_i), the value is at most B - 1 where any atom is read,
// since each atom is below 2^(b_i), and at most |c| where none is
static unsigned int keymath_form_bits(const KeymathForm &form, const std::vector<EngineRecordTerm> &terms)
{
    // a magnitude within KEYMATH_COEFFICIENT_MOST fits an unsigned word
    ExactLimbs bound = keymath_shifted((unsigned long long)keymath_magnitude(form.constant), 0ull);
    for (const std::pair<unsigned int, long long> &term : form.terms)
    {
        // a coefficient within KEYMATH_COEFFICIENT_MOST fits an unsigned word
        const unsigned long long coefficient = (unsigned long long)keymath_magnitude(term.second);
        bound = exact_sum(bound, keymath_shifted(coefficient, terms[term.first].bits));
    }
    const unsigned long long bits = exact_bit_length(form.terms.empty() ? bound : exact_less_one(bound));
    // a form's atoms are registers of at most 32 ENGINE_RECORD_LIMBS_MOST bits, and its coefficients below 2^62, so
    // its bound fits an unsigned int
    return (unsigned int)bits;
}

extern "C" long keymath_record_imprint(const KeymathRecordRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return KEYMATH_REFUSED;
    }
    EngineError *const error = request->error;
    if (!KEYMATH_HELD((request->key != NULL) && (request->steps != NULL) && (request->count != 0u)
                          && (request->outputs != NULL)
                          && (request->output_count != 0u) && (request->output_count <= request->count)
                          && (request->members != 0u) && (request->members <= ENGINE_RECORD_MEMBERS_MAX),
                      request, error, ENGINE_ERROR_REQUEST))
    {
        return KEYMATH_REFUSED;
    }
    memset(request->key, 0, sizeof(*request->key));
    std::vector<EngineRecordTerm> terms(request->count);
    std::vector<char> never_negative(request->count, 0);
    std::vector<KeymathForm> forms(request->count);
    for (unsigned int step = 0u; step < request->count; step += 1u)
    {
        const EngineRecordStep &doing = request->steps[step];
        EngineRecordTerm &term = terms[step];
        memset(&term, 0, sizeof(term));
        term.operation = doing.operation;
        term.left = doing.left;
        term.right = doing.right;
        if (!KEYMATH_HELD(!keymath_record_reads(doing.operation)
                              || ((doing.left < step)
                                  && ((doing.operation == ENGINE_RECORD_ABSOLUTE) || (doing.right < step))),
                          &doing, error, ENGINE_ERROR_REQUEST))
        {
            return KEYMATH_REFUSED;
        }
        if ((doing.operation == ENGINE_RECORD_FIELD) || (doing.operation == ENGINE_RECORD_FIELD_SIGNED))
        {
            if (!KEYMATH_HELD((request->field_bits != NULL) && (doing.left < request->fields)
                                  && (doing.member < request->members),
                              &doing, error, ENGINE_ERROR_REQUEST))
            {
                return KEYMATH_REFUSED;
            }
            term.bits = request->field_bits[doing.left];
            term.member = doing.member;
        }
        else if (doing.operation == ENGINE_RECORD_CONSTANT)
        {
            term.constant = ((unsigned long long)doing.right << 32u) | (unsigned long long)doing.left;
            term.bits = keymath_word_bits(term.constant);
        }
        else if (doing.operation == ENGINE_RECORD_PRODUCT)
        {
            term.bits = terms[doing.left].bits + terms[doing.right].bits;
        }
        else if ((doing.operation == ENGINE_RECORD_SUM) || (doing.operation == ENGINE_RECORD_DIFFERENCE))
        {
            const unsigned int wider = (terms[doing.left].bits > terms[doing.right].bits) ? terms[doing.left].bits
                                                                                        : terms[doing.right].bits;
            term.bits = wider + 1u;
        }
        else if (doing.operation == ENGINE_RECORD_LADDER)
        {
            term.bits = keymath_word_bits((unsigned long long)ENGINE_GOLDEN_RUNGS - 1ull);
        }
        else if (doing.operation == ENGINE_RECORD_ABSOLUTE)
        {
            term.bits = terms[doing.left].bits;
            term.right = doing.left;
        }
        else if (doing.operation == ENGINE_RECORD_COMPARE)
        {
            term.bits = 1u;
        }
        else if ((doing.operation == ENGINE_RECORD_QUOTIENT) || (doing.operation == ENGINE_RECORD_EXACT_QUOTIENT))
        {
            // a nonzero divisor is at least 1, so the quotient is no wider than the numerator. A constant divisor c
            // takes floor(log2 c) bits off: |left| < 2^L and c >= 2^floor(log2 c) put |left| / c below
            // 2^(L - floor(log2 c)). A zero constant narrows nothing and is refused where it divides.
            term.bits = terms[doing.left].bits;
            if (terms[doing.right].operation == ENGINE_RECORD_CONSTANT)
            {
                const unsigned int dropped = (terms[doing.right].bits == 0u) ? 0u : (terms[doing.right].bits - 1u);
                term.bits = (term.bits > dropped) ? (term.bits - dropped) : 1u;
            }
        }
        else if (doing.operation == ENGINE_RECORD_REMAINDER)
        {
            // the remainder is below both the divisor and the numerator
            term.bits = (terms[doing.left].bits < terms[doing.right].bits) ? terms[doing.left].bits
                                                                          : terms[doing.right].bits;
        }
        else if (doing.operation == ENGINE_RECORD_GCD)
        {
            // gcd(a, 0) = |a|, so only the wider operand bounds it
            term.bits = (terms[doing.left].bits > terms[doing.right].bits) ? terms[doing.left].bits
                                                                          : terms[doing.right].bits;
        }
        else if ((doing.operation == ENGINE_RECORD_XOR) || (doing.operation == ENGINE_RECORD_AND))
        {
            // both operands lie in the signed range of one bit over the wider, and so does any bitwise result there,
            // down to -2^wider, whose magnitude takes that bit. An and with a register never negative lies between 0
            // and that register, and the xor of two never negative lies below 2^wider, so neither takes the extra bit.
            const unsigned int left_bits = terms[doing.left].bits;
            const unsigned int right_bits = terms[doing.right].bits;
            const unsigned int wider = (left_bits > right_bits) ? left_bits : right_bits;
            const unsigned int narrower = (left_bits < right_bits) ? left_bits : right_bits;
            const int left_kept = (never_negative[doing.left] != 0) ? 1 : 0;
            const int right_kept = (never_negative[doing.right] != 0) ? 1 : 0;
            term.bits = wider + 1u;
            if ((doing.operation == ENGINE_RECORD_AND) && (left_kept != 0) && (right_kept != 0))
            {
                term.bits = narrower;
            }
            else if ((doing.operation == ENGINE_RECORD_AND) && ((left_kept != 0) || (right_kept != 0)))
            {
                term.bits = (left_kept != 0) ? left_bits : right_bits;
            }
            else if ((left_kept != 0) && (right_kept != 0))
            {
                term.bits = wider;
            }
        }
        else if (doing.operation == ENGINE_RECORD_WRAP)
        {
            if (!KEYMATH_HELD((doing.left < step) && (doing.right >= ENGINE_RECORD_WRAP_BITS_LEAST), &doing, error,
                              ENGINE_ERROR_REQUEST))
            {
                return KEYMATH_REFUSED;
            }
            // a register of fewer bits than the wrap already lies in its signed range and passes through; a wider one
            // lands in [-2^(right - 1), 2^(right - 1)), whose magnitude takes all `right` bits at -2^(right - 1)
            term.bits = (terms[doing.left].bits < doing.right) ? terms[doing.left].bits : doing.right;
            // the one register read is the left, as the absolute's; the width rides in the term's constant
            term.right = doing.left;
            term.constant = (unsigned long long)doing.right;
        }
        else if (doing.operation == ENGINE_RECORD_TABLE)
        {
            if (!KEYMATH_HELD((request->tables != NULL) && (doing.left < step)
                                  && (doing.right < request->table_count),
                              &doing, error, ENGINE_ERROR_REQUEST))
            {
                return KEYMATH_REFUSED;
            }
            const EngineRecordTable &table = request->tables[doing.right];
            if (!KEYMATH_HELD((table.index_bits >= 1u) && (table.index_bits <= ENGINE_RECORD_TABLE_INDEX_BITS_MOST)
                                  && (table.index_bits <= terms[doing.left].bits) && (table.out_bits != 0u)
                                  && (table.values != NULL),
                              &table, error, ENGINE_ERROR_REQUEST))
            {
                return KEYMATH_REFUSED;
            }
            term.bits = table.out_bits;
        }
        else
        {
            KEYMATH_HELD(0, &doing, error, ENGINE_ERROR_REQUEST);
            return KEYMATH_REFUSED;
        }
        const int wrap_passes = (doing.operation == ENGINE_RECORD_WRAP) && (terms[doing.left].bits < doing.right);
        // the register's form: a sum or difference adds its operands', a product by a constant scales the other's, a
        // constant is its value, and a wrap that passes its register through keeps that register's form. The form's
        // bound narrows the width the operation's own rule gave where it is tighter; where a form would outgrow its
        // words, or for any other register, the register is an atom
        KeymathForm &form = forms[step];
        int formed = 0;
        if ((doing.operation == ENGINE_RECORD_SUM) || (doing.operation == ENGINE_RECORD_DIFFERENCE))
        {
            formed = keymath_form_add(forms[doing.left], forms[doing.right],
                                      (doing.operation == ENGINE_RECORD_SUM) ? 1ll : -1ll, &form);
        }
        else if ((doing.operation == ENGINE_RECORD_PRODUCT) && forms[doing.right].terms.empty())
        {
            formed = keymath_form_scale(forms[doing.left], forms[doing.right].constant, &form);
        }
        else if ((doing.operation == ENGINE_RECORD_PRODUCT) && forms[doing.left].terms.empty())
        {
            formed = keymath_form_scale(forms[doing.right], forms[doing.left].constant, &form);
        }
        else if ((doing.operation == ENGINE_RECORD_CONSTANT)
                 && (term.constant <= (unsigned long long)KEYMATH_COEFFICIENT_MOST))
        {
            // the constant is at most KEYMATH_COEFFICIENT_MOST, so it fits a signed word
            form.constant = (long long)term.constant;
            form.terms.clear();
            formed = 1;
        }
        else if (wrap_passes != 0)
        {
            form = forms[doing.left];
            formed = 1;
        }
        if (formed != 0)
        {
            const unsigned int bound = keymath_form_bits(form, terms);
            term.bits = (bound < term.bits) ? bound : term.bits;
        }
        else
        {
            form = keymath_form_atom(step);
        }
        term.bits = (term.bits == 0u) ? 1u : term.bits;
        if (!KEYMATH_HELD(term.bits <= (32u * ENGINE_RECORD_LIMBS_MOST), &doing, error, ENGINE_ERROR_REQUEST))
        {
            return KEYMATH_REFUSED;
        }
        never_negative[step] = keymath_never_negative(doing, never_negative, wrap_passes);
    }
    for (unsigned int output = 0u; output < request->output_count; output += 1u)
    {
        if (!KEYMATH_HELD(request->outputs[output] < request->count, &request->outputs[output], error,
                          ENGINE_ERROR_REQUEST))
        {
            return KEYMATH_REFUSED;
        }
        for (unsigned int before = 0u; before < output; before += 1u)
        {
            if (!KEYMATH_HELD(request->outputs[before] != request->outputs[output], &request->outputs[output], error,
                              ENGINE_ERROR_REQUEST))
            {
                return KEYMATH_REFUSED;
            }
        }
    }
    EngineRecordKey *const key = request->key;
    key->term = (EngineRecordTerm *)malloc(terms.size() * sizeof(EngineRecordTerm));
    key->output = (unsigned int *)malloc((size_t)request->output_count * sizeof(unsigned int));
    if (!KEYMATH_HELD((key->term != NULL) && (key->output != NULL), key, error, ENGINE_ERROR_RESOURCE))
    {
        keymath_record_release(key);
        return KEYMATH_REFUSED;
    }
    memcpy(key->term, terms.data(), terms.size() * sizeof(EngineRecordTerm));
    memcpy(key->output, request->outputs, (size_t)request->output_count * sizeof(unsigned int));
    key->steps = request->count;
    key->members = request->members;
    key->outputs = request->output_count;
    key->tables = request->table_count;
    if (request->table_count != 0u)
    {
        std::vector<unsigned int> values;
        key->table = (EngineRecordTable *)malloc((size_t)request->table_count * sizeof(EngineRecordTable));
        if (!KEYMATH_HELD(key->table != NULL, key, error, ENGINE_ERROR_RESOURCE))
        {
            keymath_record_release(key);
            return KEYMATH_REFUSED;
        }
        for (unsigned int table = 0u; table < request->table_count; table += 1u)
        {
            const EngineRecordTable &source = request->tables[table];
            // index_bits is at most 32, so the entry count is at most 2^32 and fits an unsigned long long
            const unsigned long long entries = 1ull << source.index_bits;
            const unsigned int out_limbs = (source.out_bits + 31u) / 32u;
            key->table[table].index_bits = source.index_bits;
            key->table[table].out_bits = source.out_bits;
            key->table[table].values = NULL;
            values.insert(values.end(), source.values, source.values + (entries * out_limbs));
        }
        key->table_values = (unsigned int *)malloc((values.size() + 1u) * sizeof(unsigned int));
        if (!KEYMATH_HELD(key->table_values != NULL, key, error, ENGINE_ERROR_RESOURCE))
        {
            keymath_record_release(key);
            return KEYMATH_REFUSED;
        }
        memcpy(key->table_values, values.data(), values.size() * sizeof(unsigned int));
        key->table_word_count = (unsigned long long)values.size();
    }
    return (long)key->steps;
}

extern "C" void keymath_record_release(EngineRecordKey *key)
{
    free(key->term);
    free(key->output);
    free(key->table);
    free(key->table_values);
    memset(key, 0, sizeof(*key));
}
