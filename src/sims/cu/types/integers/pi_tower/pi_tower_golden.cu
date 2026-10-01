// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// pi_tower_golden.cu: residues, golden and the record program
#include "pi_tower_internal.h"

// 12. The golden helix. The residues flip
// sign each floor, a half turn, and shrink by 1 / [a_(j+1); a_(j+2), ...]: on the cylinder of angle and log size they
// step down a helix. The golden ratio [1; 1, 1, ...] shrinks by exactly 1 / phi every half turn, and every tower is at
// least as tall as its, q_j >= F_(j+1). Each residue is bracketed from the turn, (qA - pM, qA - pM + q), and every
// comparison is decided at both ends.
void pi_tower_golden(SimResults *results, const PiTowerTurn &turn, const std::vector<PiWide> &denominators,
                     const std::vector<PiWide> &floors)
{
    const PiWide bound = pi_tower_power_two(PI_TOWER_RECORD_BITS);
    std::vector<PiWide> low;
    std::vector<PiWide> high;
    PiWide numerator_before = pi_tower_unsigned(1ull);
    PiWide numerator = pi_tower_unsigned(0ull);
    PiWide fibonacci_before = pi_tower_unsigned(0ull);
    PiWide fibonacci = pi_tower_unsigned(1ull);
    int alternates = 1;
    int above_golden_floor = 1;
    int under_next = 1;
    for (size_t at = 0u; (at < denominators.size()) && (pi_tower_compare(denominators[at], bound) <= 0); at += 1u)
    {
        if (at > 0u)
        {
            const PiWide next = pi_tower_sum(pi_tower_product(floors[at], numerator), numerator_before);
            numerator_before = numerator;
            numerator = next;
        }
        // F_(j+1): F_1 = 1 at j = 0
        above_golden_floor = above_golden_floor && (pi_tower_compare(denominators[at], fibonacci) >= 0);
        const PiWide residue = pi_tower_difference(pi_tower_product(denominators[at], turn.multiplier),
                                                   pi_tower_product(numerator, turn.modulus));
        PiWide size = residue;
        size.sign = (residue.sign == 0) ? 0 : 1;
        // the real residue's size: (size, size + q) where it is positive, (size - q, size) where negative
        low.push_back((residue.sign > 0) ? size : pi_tower_difference(size, denominators[at]));
        high.push_back((residue.sign > 0) ? pi_tower_sum(size, denominators[at]) : size);
        alternates = alternates && (residue.sign == (((at & 1u) == 0u) ? 1 : -1));
        // under the next floor: |delta_j| < 1 / q_(j+1), and so under the golden 1 / F_(j+2)
        if ((at + 1u) < denominators.size())
        {
            under_next = under_next &&
                         (pi_tower_compare(pi_tower_product(high.back(), denominators[at + 1u]), turn.modulus) < 0);
        }
        const PiWide next_fibonacci = pi_tower_sum(fibonacci, fibonacci_before);
        fibonacci_before = fibonacci;
        fibonacci = next_fibonacci;
    }
    scriptura_text(&results->line, "  the golden helix: floor j (a_(j+1)), the residue's shrink |delta_j| / "
                                   "|delta_(j-1)|, against 1/phi = 0.6180\n");
    int band_ok = 1;
    int decided = 1;
    unsigned int below = 0u;
    unsigned int above = 0u;
    unsigned int banded = 0u;
    // |delta_(j-1)| = a_(j+1) |delta_j| + |delta_(j+1)| (Euclid). The shrink lies in (1 / (a_(j+1) + 1), 1 /
    // a_(j+1))
    for (size_t at = 1u; (at < low.size()) && ((at + 1u) < floors.size()); at += 1u)
    {
        // shrink below 1/phi exactly where (2 x + y)^2 < 5 y^2, x = |delta_j|, y = |delta_(j-1)|: that falls as x
        // rises and rises with y. The two corners of the bracket decide it
        const PiWide least =
            pi_tower_difference(pi_tower_product(pi_tower_unsigned(5ull), pi_tower_product(low[at - 1u], low[at - 1u])),
                                pi_tower_product(pi_tower_sum(pi_tower_sum(high[at], high[at]), low[at - 1u]),
                                                 pi_tower_sum(pi_tower_sum(high[at], high[at]), low[at - 1u])));
        const PiWide maximum = pi_tower_difference(
            pi_tower_product(pi_tower_unsigned(5ull), pi_tower_product(high[at - 1u], high[at - 1u])),
            pi_tower_product(pi_tower_sum(pi_tower_sum(low[at], low[at]), high[at - 1u]),
                             pi_tower_sum(pi_tower_sum(low[at], low[at]), high[at - 1u])));
        const int under = least.sign > 0;
        decided = decided && (least.sign == maximum.sign) && (least.sign != 0);
        below += (under != 0) ? 1u : 0u;
        above += (under == 0) ? 1u : 0u;
        // the shrink stands between 1/2 and 1 exactly on the floors of 1: 2 x > y
        const int wide = pi_tower_compare(pi_tower_sum(low[at], low[at]), high[at - 1u]) > 0;
        const int narrow = pi_tower_compare(pi_tower_sum(high[at], high[at]), low[at - 1u]) < 0;
        decided = decided && ((wide != 0) || (narrow != 0));
        const int one_floor = pi_tower_compare(floors[at + 1u], pi_tower_unsigned(1ull)) == 0;
        band_ok = band_ok && (wide == one_floor);
        banded += (wide != 0) ? 1u : 0u;
        scriptura_text(&results->line, "    ");
        scriptura_decimal(&results->line, at, 2u);
        scriptura_text(&results->line, " (");
        pi_tower_print_decimal(&results->line, floors[at + 1u]);
        scriptura_text(&results->line, ")  ");
        sim_ratio_print(&results->line, &low[at], &high[at - 1u], 4u);
        scriptura_text(&results->line, (under != 0) ? "  below the golden shrink\n" : "  above the golden shrink\n");
        sim_flush(results);
    }
    // the mean growth a floor, q_J^(1 / J), to 6 places: the largest r with r^J <= q_J 10^(6 J)
    const size_t last = low.size() - 1u;
    PiWide scaled = denominators[last];
    for (size_t place = 0u; place < (6u * last); place += 1u)
    {
        scaled = pi_tower_product(scaled, pi_tower_unsigned(10ull));
    }
    unsigned long long root_low = 1000000ull;
    unsigned long long root_high = 100000000ull;
    while ((root_high - root_low) > 1ull)
    {
        const unsigned long long middle = root_low + ((root_high - root_low) / 2ull);
        PiWide power = pi_tower_unsigned(1ull);
        for (size_t times = 0u; times < last; times += 1u)
        {
            power = pi_tower_product(power, pi_tower_unsigned(middle));
        }
        if (pi_tower_compare(power, scaled) <= 0)
        {
            root_low = middle;
        }
        else
        {
            root_high = middle;
        }
    }
    // phi = (1 + sqrt 5) / 2 to 6 places: (10^6 + floor(sqrt(5 10^12))) / 2, the root's floor taken exactly
    const unsigned long long golden =
        (1000000ull + pi_tower_word(pi_tower_root(pi_tower_unsigned(5000000000000ull)))) / 2ull;
    scriptura_text(&results->line, "    ");
    scriptura_decimal(&results->line, below, 1u);
    scriptura_text(&results->line, " floors shrink below the golden 1/phi and ");
    scriptura_decimal(&results->line, above, 1u);
    scriptura_text(&results->line, " above; ");
    scriptura_decimal(&results->line, banded, 1u);
    scriptura_text(&results->line, " shrink between 1/2 and 1, the floors of 1\n    growth a floor, q_");
    scriptura_decimal(&results->line, last, 1u);
    scriptura_text(&results->line, "^(1/");
    scriptura_decimal(&results->line, last, 1u);
    scriptura_text(&results->line, ") = ");
    scriptura_decimal(&results->line, root_low / 1000000ull, 1u);
    scriptura_character(&results->line, '.');
    scriptura_decimal(&results->line, root_low % 1000000ull, 6u);
    scriptura_text(&results->line, ", against the golden phi = ");
    scriptura_decimal(&results->line, golden / 1000000ull, 1u);
    scriptura_character(&results->line, '.');
    scriptura_decimal(&results->line, golden % 1000000ull, 6u);
    scriptura_character(&results->line, '\n');
    sim_check(results, alternates,
              "the residues flip sign on every floor, a half turn: from above on even floors, from below on odd");
    sim_check(results, above_golden_floor && under_next,
              "every floor is at least the golden one, q_j >= F_(j+1), and every residue is under the next floor's 1 / "
              "q_(j+1)");
    sim_check(results, decided && band_ok,
              "the shrink stands between 1/2 and 1 exactly where the next floor is 1, each side of 1/phi decided at "
              "both ends");
    sim_flush(results);
}

// set by an interrupt: the run stops after the sweep it is in and reports how far it reached
volatile sig_atomic_t g_pi_tower_stopped = 0;

void pi_tower_stop(int signal_number)
{
    (void)signal_number;
    g_pi_tower_stopped = 1;
}

unsigned int pi_tower_bit_length(const PiWide &value)
{
    unsigned int limb = ANCHOR_EXACT_LIMBS;
    while ((limb > 0u) && (value.limb[limb - 1u] == 0u))
    {
        limb -= 1u;
    }
    if (limb == 0u)
    {
        return 0u;
    }
    unsigned int bits = 32u * (limb - 1u);
    for (unsigned int top = value.limb[limb - 1u]; top != 0u; top >>= 1u)
    {
        bits += 1u;
    }
    return bits;
}

unsigned int pi_tower_step(std::vector<EngineRecordStep> *steps, EngineRecordOperation operation, unsigned int left,
                           unsigned int right)
{
    EngineRecordStep step;
    step.operation = operation;
    step.left = left;
    step.right = right;
    step.member = 0u;
    steps->push_back(step);
    // a program's steps are counted in an unsigned int, as keymath counts them
    return (unsigned int)(steps->size() - 1u);
}

unsigned int pi_tower_field(std::vector<EngineRecordStep> *steps, unsigned int field, unsigned int member)
{
    const unsigned int step = pi_tower_step(steps, ENGINE_RECORD_FIELD, field, 0u);
    (*steps)[step].member = member;
    return step;
}

// a register holding a non-negative integer: one constant below 2^64, and past it Horner's rule over the 32-bit limbs
// from the top, a product by 2^32 and a sum a limb
unsigned int pi_tower_constant(std::vector<EngineRecordStep> *steps, const PiWide &value)
{
    unsigned int used = ANCHOR_EXACT_LIMBS;
    while ((used > 1u) && (value.limb[used - 1u] == 0u))
    {
        used -= 1u;
    }
    if (used <= 2u)
    {
        return pi_tower_step(steps, ENGINE_RECORD_CONSTANT, value.limb[0], (used > 1u) ? value.limb[1] : 0u);
    }
    unsigned int last_step = pi_tower_step(steps, ENGINE_RECORD_CONSTANT, value.limb[used - 2u], value.limb[used - 1u]);
    for (unsigned int limb = used - 2u; limb > 0u; limb -= 1u)
    {
        const unsigned int shift = pi_tower_step(steps, ENGINE_RECORD_CONSTANT, 0u, 1u);
        last_step = pi_tower_step(steps, ENGINE_RECORD_PRODUCT, last_step, shift);
        if (value.limb[limb - 1u] != 0u)
        {
            const unsigned int low = pi_tower_step(steps, ENGINE_RECORD_CONSTANT, value.limb[limb - 1u], 0u);
            last_step = pi_tower_step(steps, ENGINE_RECORD_SUM, last_step, low);
        }
    }
    return last_step;
}

// 4 S_1 - 2 S_4 - S_5 - S_6 of a lane's four fractions, wrapped to W bits: the lane's sum mod 2^W
void pi_tower_bbp_combine(std::vector<EngineRecordStep> *steps, const unsigned int *fraction,
                          unsigned int fraction_bits)
{
    const unsigned int four = pi_tower_step(steps, ENGINE_RECORD_CONSTANT, 4u, 0u);
    const unsigned int two = pi_tower_step(steps, ENGINE_RECORD_CONSTANT, 2u, 0u);
    const unsigned int first = pi_tower_step(steps, ENGINE_RECORD_PRODUCT, four, fraction[0]);
    const unsigned int second = pi_tower_step(steps, ENGINE_RECORD_PRODUCT, two, fraction[1]);
    const unsigned int less = pi_tower_step(steps, ENGINE_RECORD_DIFFERENCE, first, second);
    const unsigned int fewer = pi_tower_step(steps, ENGINE_RECORD_DIFFERENCE, less, fraction[2]);
    const unsigned int least = pi_tower_step(steps, ENGINE_RECORD_DIFFERENCE, fewer, fraction[3]);
    pi_tower_step(steps, ENGINE_RECORD_WRAP, least, fraction_bits);
}
