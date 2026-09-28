// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// record_coherence_test_inverse.cu: broken, inverse, odd divisors and orthogonality
#include "record_coherence_test_internal.h"

// a quotient and a comparison read the whole integer: wrapping before and after them disagree on some lane
void coherence_broken(CoherenceResults *results)
{
    const unsigned int bits = 8u;
    CoherenceProgram *const program = (CoherenceProgram *)calloc(1u, sizeof(CoherenceProgram));
    const unsigned int lanes = COHERENCE_TEST_LANES;
    unsigned int *const atoms = (unsigned int *)calloc(lanes, sizeof(unsigned int));
    if ((program == NULL) || (atoms == NULL))
    {
        coherence_check(results, 0, "the broken lanes are held");
        free(program);
        free(atoms);
        return;
    }
    const unsigned int value = coherence_append(program, ENGINE_RECORD_FIELD_SIGNED, 0u, 0u);
    const unsigned int three = coherence_append(program, ENGINE_RECORD_CONSTANT, 3u, 0u);
    const unsigned int zero = coherence_append(program, ENGINE_RECORD_CONSTANT, 0u, 0u);
    const unsigned int wrapped = coherence_append(program, ENGINE_RECORD_WRAP, value, bits);
    const unsigned int quotient = coherence_append(program, ENGINE_RECORD_QUOTIENT, value, three);
    coherence_output(program, coherence_append(program, ENGINE_RECORD_WRAP, quotient, bits));
    const unsigned int quotient_wrapped = coherence_append(program, ENGINE_RECORD_QUOTIENT, wrapped, three);
    coherence_output(program, coherence_append(program, ENGINE_RECORD_WRAP, quotient_wrapped, bits));
    const unsigned int compare = coherence_append(program, ENGINE_RECORD_COMPARE, value, zero);
    coherence_output(program, coherence_append(program, ENGINE_RECORD_WRAP, compare, bits));
    const unsigned int compare_wrapped = coherence_append(program, ENGINE_RECORD_COMPARE, wrapped, zero);
    coherence_output(program, coherence_append(program, ENGINE_RECORD_WRAP, compare_wrapped, bits));
    CoherenceLoaded loaded;
    if (coherence_load(program, 1u, &loaded) == 0)
    {
        coherence_check(results, 0, "the quotient and comparison program loads");
        free(program);
        free(atoms);
        return;
    }
    for (unsigned int lane = 0u; lane < lanes; lane += 1u)
    {
        atoms[lane] = coherence_input(coherence_random());
    }
    const unsigned int out_limbs = loaded.layout.out_limbs;
    unsigned int *const host_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
    unsigned int *const device_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
    int host_ran = 0;
    int device_ran = 0;
    if ((host_out != NULL) && (device_out != NULL))
    {
        coherence_run(&loaded, atoms, lanes, host_out, device_out, &host_ran, &device_ran);
    }
    unsigned int quotient_breaks = 0u;
    unsigned int compare_breaks = 0u;
    for (unsigned int lane = 0u; host_ran && (lane < lanes); lane += 1u)
    {
        const unsigned int *const record = &device_out[(size_t)lane * out_limbs];
        const DeviceRecordStep *const table = loaded.layout.step_table;
        quotient_breaks +=
            (coherence_take(record, &table[program->outputs[0]]) != coherence_take(record, &table[program->outputs[1]]))
                ? 1u
                : 0u;
        compare_breaks +=
            (coherence_take(record, &table[program->outputs[2]]) != coherence_take(record, &table[program->outputs[3]]))
                ? 1u
                : 0u;
    }
    scriptura_text(&results->line, "  broken: the quotient by 3 disagrees on ");
    scriptura_decimal(&results->line, quotient_breaks, 1u);
    scriptura_text(&results->line, " and the comparison with 0 on ");
    scriptura_decimal(&results->line, compare_breaks, 1u);
    scriptura_text(&results->line, " of ");
    scriptura_decimal(&results->line, lanes, 1u);
    scriptura_text(&results->line, " lanes, wrapped to 8 bits before against after\n");
    coherence_check(results,
                    host_ran && device_ran &&
                        (memcmp(host_out, device_out, (size_t)lanes * out_limbs * sizeof(unsigned int)) == 0),
                    "the quotient and comparison program's device records equal the host's word for word");
    coherence_check(results, quotient_breaks != 0u, "a quotient does not commute with the wrap");
    coherence_check(results, compare_breaks != 0u, "a comparison does not commute with the wrap");
    free(host_out);
    free(device_out);
    free(atoms);
    free(program);
    coherence_free(&loaded);
}

// c^-1 modulo 2^32 for an odd c, by Newton's x(2 - cx): an odd c is its own inverse to 3 bits, and each step doubles
// the bits, 6, 12, 24, 48
static unsigned int coherence_inverse(unsigned int odd)
{
    unsigned int inverse = odd;
    for (unsigned int round = 0u; round < 4u; round += 1u)
    {
        inverse *= 2u - (odd * inverse);
    }
    return inverse;
}

// An exact quotient by an odd c is multiplication by c^-1 in Z_2. For v = c . u, the exact quotient wrapped to w equals
// the product of v wrapped to w and c^-1 modulo 2^w, wrapped to w: the division reaches into Z_2 through its
// projections.
void coherence_odd_divisors(CoherenceResults *results)
{
    static const unsigned int divisors[3] = {3u, 7u, 12345u};
    const unsigned int lanes = COHERENCE_TEST_LANES;
    unsigned int *const atoms = (unsigned int *)calloc(lanes, sizeof(unsigned int));
    CoherenceProgram *const program = (CoherenceProgram *)calloc(1u, sizeof(CoherenceProgram));
    if ((atoms == NULL) || (program == NULL))
    {
        coherence_check(results, 0, "the odd divisor lanes are held");
        free(atoms);
        free(program);
        return;
    }
    unsigned int loaded_all = 1u;
    unsigned int words_all = 1u;
    unsigned long long agreements = 0ull;
    unsigned long long comparisons = 0ull;
    for (unsigned int pick = 0u; pick < 3u; pick += 1u)
    {
        const unsigned int divisor = divisors[pick];
        const unsigned int inverse = coherence_inverse(divisor);
        memset(program, 0, sizeof(*program));
        const unsigned int factor = coherence_append(program, ENGINE_RECORD_FIELD_SIGNED, 0u, 0u);
        const unsigned int constant = coherence_append(program, ENGINE_RECORD_CONSTANT, divisor, 0u);
        const unsigned int product = coherence_append(program, ENGINE_RECORD_PRODUCT, factor, constant);
        const unsigned int quotient = coherence_append(program, ENGINE_RECORD_EXACT_QUOTIENT, product, constant);
        for (unsigned int width = 0u; width < COHERENCE_TEST_WIDTHS; width += 1u)
        {
            const unsigned int bits = s_coherence_widths[width];
            // c^-1 modulo 2^w, never negative, as a constant
            const unsigned int kept = (bits == 32u) ? inverse : (inverse & ((1u << bits) - 1u));
            coherence_output(program, coherence_append(program, ENGINE_RECORD_WRAP, quotient, bits));
            const unsigned int projected = coherence_append(program, ENGINE_RECORD_WRAP, product, bits);
            const unsigned int unit = coherence_append(program, ENGINE_RECORD_CONSTANT, kept, 0u);
            const unsigned int times = coherence_append(program, ENGINE_RECORD_PRODUCT, projected, unit);
            coherence_output(program, coherence_append(program, ENGINE_RECORD_WRAP, times, bits));
        }
        CoherenceLoaded loaded;
        if (coherence_load(program, 1u, &loaded) == 0)
        {
            loaded_all = 0u;
            continue;
        }
        for (unsigned int lane = 0u; lane < lanes; lane += 1u)
        {
            atoms[lane] = coherence_input(coherence_random());
        }
        const unsigned int out_limbs = loaded.layout.out_limbs;
        unsigned int *const host_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
        unsigned int *const device_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
        int host_ran = 0;
        int device_ran = 0;
        if ((host_out != NULL) && (device_out != NULL))
        {
            coherence_run(&loaded, atoms, lanes, host_out, device_out, &host_ran, &device_ran);
        }
        words_all = words_all && host_ran && device_ran &&
                    (memcmp(host_out, device_out, (size_t)lanes * out_limbs * sizeof(unsigned int)) == 0);
        for (unsigned int lane = 0u; host_ran && (lane < lanes); lane += 1u)
        {
            const unsigned int *const record = &device_out[(size_t)lane * out_limbs];
            const long long factor_value = coherence_signed_input(atoms[lane]);
            for (unsigned int width = 0u; width < COHERENCE_TEST_WIDTHS; width += 1u)
            {
                const DeviceRecordStep *const table = loaded.layout.step_table;
                const long long divided = coherence_take(record, &table[program->outputs[2u * width]]);
                const long long multiplied = coherence_take(record, &table[program->outputs[(2u * width) + 1u]]);
                // the factor itself, wrapped: what both must be
                const long long expected =
                    coherence_reduce((unsigned long long)factor_value, s_coherence_widths[width]);
                comparisons += 1ull;
                agreements += ((divided == expected) && (multiplied == expected)) ? 1ull : 0ull;
            }
        }
        free(host_out);
        free(device_out);
        coherence_free(&loaded);
    }
    scriptura_text(&results->line, "  odd divisors: 3, 7 and 12345; ");
    scriptura_decimal(&results->line, agreements, 1u);
    scriptura_text(&results->line, " of ");
    scriptura_decimal(&results->line, comparisons, 1u);
    scriptura_text(&results->line,
                   " lane-widths: the exact quotient wrapped equals the wrapped product by c^-1 mod 2^w\n");
    coherence_check(results, loaded_all, "every odd divisor program loads");
    coherence_check(results, words_all, "the odd divisor programs' device records equal the host's word for word");
    coherence_check(results, (comparisons != 0ull) && (agreements == comparisons),
                    "an exact quotient by an odd c is the product by c^-1 in every projection");
    free(atoms);
    free(program);
}

#define COHERENCE_TEST_MODULI 4u

// the odd crystals' windows: 3^5, 3^10, 5^4 and 7^3
static const unsigned int s_coherence_moduli[COHERENCE_TEST_MODULI] = {243u, 59049u, 625u, 343u};

// the 2-adic window the odd crystals are joined to
#define COHERENCE_TEST_JOIN_BITS 8u

// a residue in [0, m)
static long long coherence_residue(long long value, long long modulus)
{
    const long long residue = value % modulus;
    return (residue < 0ll) ? (residue + modulus) : residue;
}

// the orthogonal crystals. A remainder by an odd prime power m = p^v is the projection onto Z / p^v, and a program of
// sums, differences and products commutes with it as the wrap does with 2^w: the exact run's remainder, the run
// reduced at every step and the host's own arithmetic modulo m agree on every lane. The 2-adic window and the p-adic
// one are independent (Z / 2^w p^v = Z / 2^w x Z / p^v). The machine joins them: y = y_2 + 2^w ((y_p - y_2)
// 2^-w mod m) must equal the exact run modulo 2^w m. An xor is the 2-adic crystal's alone and must break modulo 3.
void coherence_orthogonal(CoherenceResults *results)
{
    const unsigned int lanes = COHERENCE_TEST_LANES;
    const long long join = 1ll << COHERENCE_TEST_JOIN_BITS;
    unsigned int *const atoms = (unsigned int *)calloc((size_t)lanes * COHERENCE_TEST_INPUTS, sizeof(unsigned int));
    CoherenceProgram *const program = (CoherenceProgram *)calloc(1u, sizeof(CoherenceProgram));
    if ((atoms == NULL) || (program == NULL))
    {
        coherence_check(results, 0, "the orthogonal lanes are held");
        free(atoms);
        free(program);
        return;
    }
    unsigned int loaded_all = 1u;
    unsigned int words_all = 1u;
    unsigned long long agreements = 0ull;
    unsigned long long joined = 0ull;
    unsigned long long comparisons = 0ull;
    for (unsigned int drawn = 0u; drawn < COHERENCE_TEST_PROGRAMS; drawn += 1u)
    {
        CoherenceOperation operations[COHERENCE_TEST_OPERATIONS];
        coherence_draw(operations, 1);
        memset(program, 0, sizeof(*program));
        unsigned int value[COHERENCE_TEST_INPUTS + COHERENCE_TEST_OPERATIONS];
        for (unsigned int input = 0u; input < COHERENCE_TEST_INPUTS; input += 1u)
        {
            value[input] = coherence_append(program, ENGINE_RECORD_FIELD_SIGNED, input, 0u);
        }
        for (unsigned int at = 0u; at < COHERENCE_TEST_OPERATIONS; at += 1u)
        {
            value[COHERENCE_TEST_INPUTS + at] = coherence_append(
                program, operations[at].operation, value[operations[at].left], value[operations[at].right]);
        }
        const unsigned int exact = value[COHERENCE_TEST_INPUTS + COHERENCE_TEST_OPERATIONS - 1u];
        const unsigned int two_adic = coherence_append(program, ENGINE_RECORD_WRAP, exact, COHERENCE_TEST_JOIN_BITS);
        const unsigned int scale = coherence_append(program, ENGINE_RECORD_CONSTANT, (unsigned int)join, 0u);
        for (unsigned int pick = 0u; pick < COHERENCE_TEST_MODULI; pick += 1u)
        {
            const long long modulus = (long long)s_coherence_moduli[pick];
            // 2^-w modulo m, found by trial: m is odd. It exists below m
            long long unit = 1ll;
            while (((unit * join) % modulus) != 1ll)
            {
                unit += 1ll;
            }
            const unsigned int window = coherence_append(program, ENGINE_RECORD_CONSTANT, s_coherence_moduli[pick], 0u);
            const unsigned int projected = coherence_append(program, ENGINE_RECORD_REMAINDER, exact, window);
            coherence_output(program, projected);
            unsigned int reduced[COHERENCE_TEST_INPUTS + COHERENCE_TEST_OPERATIONS];
            for (unsigned int input = 0u; input < COHERENCE_TEST_INPUTS; input += 1u)
            {
                reduced[input] = coherence_append(program, ENGINE_RECORD_REMAINDER, value[input], window);
            }
            for (unsigned int at = 0u; at < COHERENCE_TEST_OPERATIONS; at += 1u)
            {
                const unsigned int step = coherence_append(program, operations[at].operation,
                                                           reduced[operations[at].left], reduced[operations[at].right]);
                reduced[COHERENCE_TEST_INPUTS + at] = coherence_append(program, ENGINE_RECORD_REMAINDER, step, window);
            }
            coherence_output(program, reduced[COHERENCE_TEST_INPUTS + COHERENCE_TEST_OPERATIONS - 1u]);
            // the join: y_2 + 2^w (((y_p - y_2) 2^-w) rem m), from the machine's two windows alone
            const unsigned int apart = coherence_append(program, ENGINE_RECORD_DIFFERENCE, projected, two_adic);
            const unsigned int inverse = coherence_append(program, ENGINE_RECORD_CONSTANT, (unsigned int)unit, 0u);
            const unsigned int lifted = coherence_append(program, ENGINE_RECORD_PRODUCT, apart, inverse);
            const unsigned int digit = coherence_append(program, ENGINE_RECORD_REMAINDER, lifted, window);
            const unsigned int placed = coherence_append(program, ENGINE_RECORD_PRODUCT, digit, scale);
            coherence_output(program, coherence_append(program, ENGINE_RECORD_SUM, two_adic, placed));
            // the exact run's remainder by 2^w m, what the join must equal modulo 2^w m
            const unsigned int constant_step =
                coherence_append(program, ENGINE_RECORD_CONSTANT, (unsigned int)(join * modulus), 0u);
            coherence_output(program, coherence_append(program, ENGINE_RECORD_REMAINDER, exact, constant_step));
        }
        CoherenceLoaded loaded;
        if (coherence_load(program, COHERENCE_TEST_INPUTS, &loaded) == 0)
        {
            loaded_all = 0u;
            continue;
        }
        for (unsigned int at = 0u; at < lanes * COHERENCE_TEST_INPUTS; at += 1u)
        {
            atoms[at] = coherence_input(coherence_random());
        }
        const unsigned int out_limbs = loaded.layout.out_limbs;
        unsigned int *const host_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
        unsigned int *const device_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
        int host_ran = 0;
        int device_ran = 0;
        if ((host_out != NULL) && (device_out != NULL))
        {
            coherence_run(&loaded, atoms, lanes, host_out, device_out, &host_ran, &device_ran);
        }
        words_all = words_all && host_ran && device_ran &&
                    (memcmp(host_out, device_out, (size_t)lanes * out_limbs * sizeof(unsigned int)) == 0);
        for (unsigned int lane = 0u; host_ran && (lane < lanes); lane += 1u)
        {
            const unsigned int *const record = &device_out[(size_t)lane * out_limbs];
            const DeviceRecordStep *const table = loaded.layout.step_table;
            for (unsigned int pick = 0u; pick < COHERENCE_TEST_MODULI; pick += 1u)
            {
                const long long modulus = (long long)s_coherence_moduli[pick];
                // the third reckoning: the host's own arithmetic, reduced modulo m at every step
                long long host[COHERENCE_TEST_INPUTS + COHERENCE_TEST_OPERATIONS];
                for (unsigned int input = 0u; input < COHERENCE_TEST_INPUTS; input += 1u)
                {
                    host[input] =
                        coherence_residue(coherence_signed_input(atoms[lane * COHERENCE_TEST_INPUTS + input]), modulus);
                }
                for (unsigned int at = 0u; at < COHERENCE_TEST_OPERATIONS; at += 1u)
                {
                    const long long left = host[operations[at].left];
                    const long long right = host[operations[at].right];
                    // each residue is below 59049. A product stays far inside the word
                    const long long step =
                        (operations[at].operation == ENGINE_RECORD_SUM)
                            ? (left + right)
                            : ((operations[at].operation == ENGINE_RECORD_DIFFERENCE) ? (left - right)
                                                                                      : (left * right));
                    host[COHERENCE_TEST_INPUTS + at] = coherence_residue(step, modulus);
                }
                const long long expected = host[COHERENCE_TEST_INPUTS + COHERENCE_TEST_OPERATIONS - 1u];
                const long long projected = coherence_take(record, &table[program->outputs[4u * pick]]);
                const long long stepped = coherence_take(record, &table[program->outputs[(4u * pick) + 1u]]);
                const long long rebuilt = coherence_take(record, &table[program->outputs[(4u * pick) + 2u]]);
                const long long integer_part = coherence_take(record, &table[program->outputs[(4u * pick) + 3u]]);
                comparisons += 1ull;
                agreements += ((coherence_residue(projected, modulus) == expected) &&
                               (coherence_residue(stepped, modulus) == expected))
                                  ? 1ull
                                  : 0ull;
                joined += (coherence_residue(rebuilt - integer_part, join * modulus) == 0ll) ? 1ull : 0ull;
            }
        }
        free(host_out);
        free(device_out);
        coherence_free(&loaded);
    }
    // the xor modulo 3: the xor of the residues against the residue of the xor
    memset(program, 0, sizeof(*program));
    const unsigned int left = coherence_append(program, ENGINE_RECORD_FIELD_SIGNED, 0u, 0u);
    const unsigned int right = coherence_append(program, ENGINE_RECORD_FIELD_SIGNED, 1u, 0u);
    const unsigned int three = coherence_append(program, ENGINE_RECORD_CONSTANT, 3u, 0u);
    coherence_output(program, coherence_append(program, ENGINE_RECORD_REMAINDER,
                                               coherence_append(program, ENGINE_RECORD_XOR, left, right), three));
    const unsigned int left_residue = coherence_append(program, ENGINE_RECORD_REMAINDER, left, three);
    const unsigned int right_residue = coherence_append(program, ENGINE_RECORD_REMAINDER, right, three);
    coherence_output(
        program, coherence_append(program, ENGINE_RECORD_REMAINDER,
                                  coherence_append(program, ENGINE_RECORD_XOR, left_residue, right_residue), three));
    unsigned int xor_breaks = 0u;
    CoherenceLoaded loaded;
    const int xor_loads = coherence_load(program, 2u, &loaded);
    if (xor_loads != 0)
    {
        for (unsigned int at = 0u; at < lanes * 2u; at += 1u)
        {
            atoms[at] = coherence_input(coherence_random());
        }
        const unsigned int out_limbs = loaded.layout.out_limbs;
        unsigned int *const host_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
        unsigned int *const device_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
        int host_ran = 0;
        int device_ran = 0;
        if ((host_out != NULL) && (device_out != NULL))
        {
            coherence_run(&loaded, atoms, lanes, host_out, device_out, &host_ran, &device_ran);
        }
        words_all = words_all && host_ran && device_ran &&
                    (memcmp(host_out, device_out, (size_t)lanes * out_limbs * sizeof(unsigned int)) == 0);
        for (unsigned int lane = 0u; host_ran && (lane < lanes); lane += 1u)
        {
            const unsigned int *const record = &device_out[(size_t)lane * out_limbs];
            const long long integer_part = coherence_take(record, &loaded.layout.step_table[program->outputs[0]]);
            const long long parts = coherence_take(record, &loaded.layout.step_table[program->outputs[1]]);
            xor_breaks += (coherence_residue(integer_part, 3ll) != coherence_residue(parts, 3ll)) ? 1u : 0u;
        }
        free(host_out);
        free(device_out);
        coherence_free(&loaded);
    }
    scriptura_text(&results->line, "  orthogonal crystals: 3^5, 3^10, 5^4 and 7^3 over ");
    scriptura_decimal(&results->line, COHERENCE_TEST_PROGRAMS, 1u);
    scriptura_text(&results->line, " ring programs; ");
    scriptura_decimal(&results->line, agreements, 1u);
    scriptura_text(&results->line, " of ");
    scriptura_decimal(&results->line, comparisons, 1u);
    scriptura_text(&results->line, " lane-moduli agree three ways, ");
    scriptura_decimal(&results->line, joined, 1u);
    scriptura_text(&results->line, " join with the 8-bit window exactly; the xor breaks modulo 3 on ");
    scriptura_decimal(&results->line, xor_breaks, 1u);
    scriptura_text(&results->line, " of ");
    scriptura_decimal(&results->line, lanes, 1u);
    scriptura_text(&results->line, " lanes\n");
    coherence_check(results, loaded_all && (xor_loads != 0), "every orthogonal program loads");
    coherence_check(results, words_all, "the orthogonal programs' device records equal the host's word for word");
    coherence_check(results, (comparisons != 0ull) && (agreements == comparisons),
                    "a ring program commutes with the projection onto Z / p^v for p = 3, 5 and 7");
    coherence_check(results, joined == comparisons,
                    "the machine joins the 2-adic and p-adic windows into the exact run modulo 2^w p^v");
    coherence_check(results, xor_breaks != 0u, "an xor is the 2-adic crystal's alone: it breaks modulo 3");
    free(atoms);
    free(program);
}

// |x| as an unsigned word, for the row a magnitude-indexed table reads
unsigned long long coherence_magnitude(long long value)
{
    // a negative word negated in unsigned arithmetic is its magnitude, the most negative one included
    return (value < 0ll) ? (0ull - (unsigned long long)value) : (unsigned long long)value;
}
