// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// record_boundary_test_codes.cu: counts, primes, determinants and codes
#include "record_boundary_test_internal.h"

// Haar measure counted: a tower of 4 samples and one level, whose range each way is 3 bits. Every input quantum at
// level w + 3 runs through the map and the output's quantum at level w is tallied. The map's low w bits read only the
// inputs' low w + 3. The map on quanta is well defined, and a map that keeps Haar measure sends exactly 2^(4 . 3)
// input quanta onto every output quantum, from any window of representatives.
void boundary_counted(BoundaryResults *results)
{
    const unsigned int samples = BOUNDARY_TEST_COUNT_SAMPLES;
    unsigned int runs = 0u;
    unsigned int balanced = 0u;
    int ran_all = 1;
    for (unsigned int inverse = 0u; inverse < 2u; inverse += 1u)
    {
        BoundaryProgram *const program = (BoundaryProgram *)calloc(1u, sizeof(BoundaryProgram));
        BoundaryTower *const tower = (BoundaryTower *)calloc(1u, sizeof(BoundaryTower));
        if ((program == NULL) || (tower == NULL))
        {
            ran_all = 0;
            free(program);
            free(tower);
            continue;
        }
        unsigned int fields[BOUNDARY_TEST_COUNT_SAMPLES];
        for (unsigned int at = 0u; at < samples; at += 1u)
        {
            fields[at] = boundary_append(program, ENGINE_RECORD_FIELD_SIGNED, at, 0u);
            tower->low[0][at] = fields[at];
        }
        const unsigned int *mapped = tower->crystal;
        if (inverse == 0u)
        {
            boundary_forward(program, tower, samples, 1u);
        }
        else
        {
            boundary_inverse(program, fields, NULL, NULL, tower, samples, 1u);
            mapped = tower->low[0];
        }
        for (unsigned int at = 0u; at < samples; at += 1u)
        {
            boundary_output(program, mapped[at]);
        }
        BoundaryLoaded loaded;
        if (boundary_load(program, samples, &loaded) == 0)
        {
            ran_all = 0;
            free(program);
            free(tower);
            continue;
        }
        for (unsigned int width = 1u; width <= 2u; width += 1u)
        {
            const unsigned int digit = width + BOUNDARY_TEST_COUNT_RANGE;
            const unsigned int lanes = 1u << (samples * digit);
            const unsigned int buckets = 1u << (samples * width);
            const unsigned int out_limbs = loaded.layout.out_limbs;
            for (unsigned int shifted = 0u; shifted < 2u; shifted += 1u)
            {
                // representatives from [0, 2^(w+3)) or from [-2^(w+2), 2^(w+2))
                const long long window = (shifted == 0u) ? 0ll : -(1ll << (digit - 1u));
                unsigned int *const atoms = (unsigned int *)calloc((size_t)lanes * samples, sizeof(unsigned int));
                unsigned int *const host_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
                unsigned int *const device_out =
                    (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
                unsigned int *const tallied = (unsigned int *)calloc(buckets, sizeof(unsigned int));
                const int buffers = (atoms != NULL) && (host_out != NULL) && (device_out != NULL) && (tallied != NULL);
                for (unsigned int lane = 0u; (buffers != 0) && (lane < lanes); lane += 1u)
                {
                    for (unsigned int at = 0u; at < samples; at += 1u)
                    {
                        const long long quantum = (long long)((lane >> (at * digit)) & ((1u << digit) - 1u));
                        atoms[((size_t)lane * samples) + at] = boundary_word(quantum + window);
                    }
                }
                const int ran = (buffers != 0) && (boundary_run(&loaded, atoms, lanes, host_out, device_out) != 0);
                ran_all = ran_all && ran && boundary_narrow_enough(&loaded, program);
                for (unsigned int lane = 0u; (ran != 0) && (lane < lanes); lane += 1u)
                {
                    unsigned int bucket = 0u;
                    for (unsigned int at = 0u; at < samples; at += 1u)
                    {
                        const long long value = boundary_read(&device_out[(size_t)lane * out_limbs],
                                                              &loaded.layout.step_table[program->outputs[at]]);
                        // the value's low w bits of two's complement are its quantum at level w
                        const unsigned int quantum =
                            (unsigned int)((unsigned long long)value & ((1ull << width) - 1ull));
                        bucket |= quantum << (at * width);
                    }
                    tallied[bucket] += 1u;
                }
                int even = ran;
                for (unsigned int bucket = 0u; bucket < buckets; bucket += 1u)
                {
                    even = even && (tallied[bucket] == (lanes / buckets));
                }
                runs += 1u;
                balanced += (even != 0) ? 1u : 0u;
                free(atoms);
                free(host_out);
                free(device_out);
                free(tallied);
            }
        }
        boundary_free(&loaded);
        free(program);
        free(tower);
    }
    scriptura_text(&results->line,
                   "  counted: T and T^-1 over 4 samples and one level, every input quantum at level w + 3 for w = 1 "
                   "and 2, from two windows; ");
    scriptura_decimal(&results->line, balanced, 1u);
    scriptura_text(&results->line, " of ");
    scriptura_decimal(&results->line, runs, 1u);
    scriptura_text(&results->line, " runs send exactly 4096 input quanta onto every output quantum\n");
    boundary_check(results, ran_all != 0, "the counted towers run on the host and the device, word for word");
    boundary_check(
        results, (runs == 8u) && (balanced == runs),
        "T and T^-1 keep Haar measure: every output quantum at level w has 2^12 input quanta at level w + 3");
}

static unsigned long long boundary_power_mod(unsigned long long base, unsigned long long exponent,
                                             unsigned long long modulus)
{
    unsigned long long result = 1ull % modulus;
    unsigned long long square = base % modulus;
    while (exponent != 0ull)
    {
        if ((exponent & 1ull) != 0ull)
        {
            result = (result * square) % modulus;
        }
        square = (square * square) % modulus;
        exponent >>= 1u;
    }
    return result;
}

// the greatest prime below `above`, by trial division
unsigned long long boundary_prime_below(unsigned long long above)
{
    for (unsigned long long candidate = above - 1ull; candidate > 2ull; candidate -= 1ull)
    {
        int prime = (candidate & 1ull) != 0ull;
        for (unsigned long long divisor = 3ull; (prime != 0) && ((divisor * divisor) <= candidate); divisor += 2ull)
        {
            prime = (candidate % divisor) != 0ull;
        }
        if (prime != 0)
        {
            return candidate;
        }
    }
    return 2ull;
}

// a matrix's determinant modulo a prime below 2^31, by elimination over Z/p
static unsigned long long boundary_determinant_mod(const long long (*matrix)[BOUNDARY_TEST_SAMPLES],
                                                   unsigned long long prime)
{
    static unsigned long long s_work[BOUNDARY_TEST_SAMPLES][BOUNDARY_TEST_SAMPLES];
    const unsigned int n = BOUNDARY_TEST_SAMPLES;
    for (unsigned int row = 0u; row < n; row += 1u)
    {
        for (unsigned int column = 0u; column < n; column += 1u)
        {
            // the residue in [0, p): a prime below 2^31 fits a long long's range as is
            const long long residue = matrix[row][column] % (long long)prime;
            s_work[row][column] = (unsigned long long)((residue < 0ll) ? (residue + (long long)prime) : residue);
        }
    }
    unsigned long long determinant = 1ull;
    for (unsigned int column = 0u; column < n; column += 1u)
    {
        unsigned int pivot = column;
        while ((pivot < n) && (s_work[pivot][column] == 0ull))
        {
            pivot += 1u;
        }
        if (pivot == n)
        {
            return 0ull;
        }
        if (pivot != column)
        {
            for (unsigned int at = 0u; at < n; at += 1u)
            {
                const unsigned long long temporary = s_work[pivot][at];
                s_work[pivot][at] = s_work[column][at];
                s_work[column][at] = temporary;
            }
            determinant = (prime - determinant) % prime;
        }
        determinant = (determinant * s_work[column][column]) % prime;
        const unsigned long long inverse = boundary_power_mod(s_work[column][column], prime - 2ull, prime);
        for (unsigned int row = column + 1u; row < n; row += 1u)
        {
            const unsigned long long factor = (s_work[row][column] * inverse) % prime;
            for (unsigned int at = column; at < n; at += 1u)
            {
                s_work[row][at] = (s_work[row][at] + prime - ((factor * s_work[column][at]) % prime)) % prime;
            }
        }
    }
    return determinant;
}

// the determinant of 2^RANGE M against +-2^(RANGE . n), modulo enough primes that their product passes Hadamard's
// bound on |det - (+-2^(RANGE . n))|: agreement modulo all of them is equality. The sign found comes back in `sign`.
static int boundary_unimodular(const long long (*matrix)[BOUNDARY_TEST_SAMPLES], int *sign, double *bound_bits)
{
    const unsigned int n = BOUNDARY_TEST_SAMPLES;
    double hadamard = 0.0;
    for (unsigned int column = 0u; column < n; column += 1u)
    {
        double norm = 0.0;
        for (unsigned int row = 0u; row < n; row += 1u)
        {
            norm += (double)matrix[row][column] * (double)matrix[row][column];
        }
        hadamard += 0.5 * log2(norm);
    }
    const double scale_bits = (double)(BOUNDARY_TEST_RANGE * n);
    const double needed = ((hadamard > scale_bits) ? hadamard : scale_bits) + 2.0;
    *bound_bits = needed;
    double product_bits = 0.0;
    unsigned int plus = 0u;
    unsigned int minus = 0u;
    unsigned int primes = 0u;
    unsigned long long prime = 1ull << 31u;
    while (product_bits <= needed)
    {
        prime = boundary_prime_below(prime);
        const unsigned long long determinant = boundary_determinant_mod(matrix, prime);
        const unsigned long long scale = boundary_power_mod(2ull, (unsigned long long)BOUNDARY_TEST_RANGE * n, prime);
        plus += (determinant == scale) ? 1u : 0u;
        minus += (determinant == ((prime - scale) % prime)) ? 1u : 0u;
        primes += 1u;
        product_bits += log2((double)prime);
    }
    *sign = (plus == primes) ? 1 : ((minus == primes) ? -1 : 0);
    return *sign != 0;
}

// the rational maps' volumes: det M and det M^-1 are +-1 exactly, and M times M^-1 is the identity
void boundary_volume(BoundaryResults *results)
{
    int forward_sign = 0;
    int inverse_sign = 0;
    double forward_bits = 0.0;
    double inverse_bits = 0.0;
    const int forward = boundary_unimodular(s_boundary_forward_matrix, &forward_sign, &forward_bits);
    const int inverse = boundary_unimodular(s_boundary_inverse_matrix, &inverse_sign, &inverse_bits);
    int identity = 1;
    for (unsigned int row = 0u; row < BOUNDARY_TEST_SAMPLES; row += 1u)
    {
        for (unsigned int column = 0u; column < BOUNDARY_TEST_SAMPLES; column += 1u)
        {
            long long entry = 0ll;
            for (unsigned int at = 0u; at < BOUNDARY_TEST_SAMPLES; at += 1u)
            {
                entry += s_boundary_forward_matrix[row][at] * s_boundary_inverse_matrix[at][column];
            }
            identity = identity && (entry == ((row == column) ? (1ll << (2u * BOUNDARY_TEST_RANGE)) : 0ll));
        }
    }
    scriptura_text(&results->line, "  volume: det M = ");
    scriptura_signed(&results->line, forward_sign);
    scriptura_text(&results->line, " and det M^-1 = ");
    scriptura_signed(&results->line, inverse_sign);
    scriptura_text(&results->line, " exactly, by primes past ");
    scriptura_decimal(&results->line, (unsigned long long)forward_bits, 1u);
    scriptura_text(&results->line, " and ");
    scriptura_decimal(&results->line, (unsigned long long)inverse_bits, 1u);
    scriptura_text(&results->line, " bits; M M^-1 = I ");
    scriptura_text(&results->line, (identity != 0) ? "holds\n" : "fails\n");
    boundary_check(results, (forward != 0) && (inverse != 0), "T and T^-1 keep volume: det M = det M^-1 = +-1 exactly");
    boundary_check(results, identity, "T^-1's matrix is the inverse of T's");
}

// a value's residue modulo a register's modulus in [0, m): the remainder carries the value's sign. M is added and
// the remainder taken again
static unsigned int boundary_code_reduce(BoundaryProgram *program, unsigned int value, unsigned int modulus)
{
    const unsigned int signed_residue = boundary_append(program, ENGINE_RECORD_REMAINDER, value, modulus);
    const unsigned int lifted = boundary_append(program, ENGINE_RECORD_SUM, signed_residue, modulus);
    return boundary_append(program, ENGINE_RECORD_REMAINDER, lifted, modulus);
}

// Garner's mixed radix over the chosen moduli: the one value below their product with the chosen residues,
// x = a_0 + m_0 (a_1 + m_1 (a_2 + ...)), each digit a_j = (... ((r_j - a_0) m_0^-1 - a_1) m_1^-1 ...) mod m_j. Every
// constant is below 2^12, and the inverses come from Fermat, each modulus prime.
unsigned int boundary_code_garner(BoundaryProgram *program, const unsigned int *residue, const unsigned int *chosen,
                                  unsigned int count)
{
    unsigned int digit[BOUNDARY_TEST_CODE_MODULI];
    for (unsigned int j = 0u; j < count; j += 1u)
    {
        const unsigned long long modulus = s_boundary_moduli[chosen[j]];
        const unsigned int modulus_register =
            boundary_append(program, ENGINE_RECORD_CONSTANT, s_boundary_moduli[chosen[j]], 0u);
        unsigned int value = residue[chosen[j]];
        for (unsigned int i = 0u; i < j; i += 1u)
        {
            const unsigned long long inverse =
                boundary_power_mod(s_boundary_moduli[chosen[i]] % modulus, modulus - 2ull, modulus);
            // the inverse is below the modulus, below 2^12
            const unsigned int inverse_register =
                boundary_append(program, ENGINE_RECORD_CONSTANT, (unsigned int)inverse, 0u);
            const unsigned int apart = boundary_append(program, ENGINE_RECORD_DIFFERENCE, value, digit[i]);
            const unsigned int scaled = boundary_append(program, ENGINE_RECORD_PRODUCT, apart, inverse_register);
            value = boundary_code_reduce(program, scaled, modulus_register);
        }
        digit[j] = value;
    }
    unsigned int top_digit = digit[count - 1u];
    for (unsigned int j = count - 1u; j >= 1u; j -= 1u)
    {
        const unsigned int radix =
            boundary_append(program, ENGINE_RECORD_CONSTANT, s_boundary_moduli[chosen[j - 1u]], 0u);
        const unsigned int placed = boundary_append(program, ENGINE_RECORD_PRODUCT, top_digit, radix);
        top_digit = boundary_append(program, ENGINE_RECORD_SUM, digit[j - 1u], placed);
    }
    return top_digit;
}

// 1 where a value that is never negative lies at or past the legal range 2^22, 0 inside it: its quotient by the range
// is 0 exactly inside, and the comparison with 0 reads that
unsigned int boundary_code_outside(BoundaryProgram *program, unsigned int value, unsigned int range, unsigned int zero)
{
    const unsigned int above = boundary_append(program, ENGINE_RECORD_QUOTIENT, value, range);
    return boundary_append(program, ENGINE_RECORD_COMPARE, above, zero);
}
