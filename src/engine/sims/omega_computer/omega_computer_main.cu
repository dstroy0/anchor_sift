// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// omega_computer_main.cu: direct runs, requests and main
#include "omega_computer_internal.h"

// Tromp's universal machine, 190 bits: (\1 (\(\\(\\1 (\\2 (1 4) (5 1 (1 1 1)))) (\3 (\2 (3 (\\3 (\\2 3 (1 4))))
// (4 (\4 (\3 1 (2 1))))))) (1 1)) (\1 (2 2))) (\1 1)
static const char s_omega_computer_universal[] =
    "0100010110000100000100000110000001011100110111100101111110100101101010000111100001011100111100000011110000001011"
    "101110011011110011111000011111000010111101001110100110100001100111011000011010";

// Tromp's delimit, 326 bits: reads a Levenshtein code and returns the number it codes as bits
static const char s_omega_computer_delimit[] =
    "0101000110100000000110000101100111100000100101111101111000010101100000000110000111110000001011111101100101111110"
    "1100101111010011101011110001000000101110010101000110100000000001011000010101111110111110000001010111101111101111"
    "110000101100000010111111101011011100000011111100001011011110111001111010000001011000001101100010000010";

// Tromp's test for uni.lam: this after delimit, and the list it must give
static const char s_omega_computer_delimit_input[] = "1111000111001";

static const char s_omega_computer_delimit_output[] = "11010";

// the direct run by rewriting: the program applied to its input's list
static OmegaComputerFate omega_computer_direct(const std::vector<int> &program, const std::string &input,
                                               unsigned int steps, unsigned int tokens, std::vector<int> &normal,
                                               unsigned long long *taken)
{
    normal.clear();
    normal.push_back(OMEGA_COMPUTER_APPLY);
    normal.insert(normal.end(), program.begin(), program.end());
    omega_computer_list_tokens(input, normal);
    return omega_computer_rewrite(normal, steps, tokens, taken);
}

static void omega_computer_binary(ScripturaLine *line, unsigned long long numerator, unsigned int bits)
{
    scriptura_text(line, "0.");
    for (unsigned int bit = bits; bit > 0u; bit -= 1u)
    {
        scriptura_character(line, (((numerator >> (bit - 1u)) & 1ull) != 0ull) ? '1' : '0');
    }
}

// the leading bits a value strictly between low and high over 2^bits is proven to have
static unsigned int omega_computer_proven(unsigned long long low, unsigned long long high, unsigned int bits)
{
    unsigned int proven = 0u;
    for (unsigned int place = 1u; place <= bits; place += 1u)
    {
        const unsigned int shift = bits - place;
        const unsigned long long floor_low = low >> shift;
        // the value is below high. Its first `place` bits are at most ceil(high / 2^shift) - 1
        const unsigned long long top = ((high + ((1ull << shift) - 1ull)) >> shift) - 1ull;
        if (floor_low != top)
        {
            break;
        }
        proven = place;
    }
    return proven;
}

static int omega_computer_request(const char *text, unsigned long long least, unsigned long long maximum,
                                  unsigned long long *value)
{
    unsigned long long read = 0ull;
    if ((text == NULL) || (text[0] == '\0'))
    {
        return 0;
    }
    for (const char *walk = text; *walk != '\0'; walk += 1)
    {
        if ((*walk < '0') || (*walk > '9') || (read > maximum))
        {
            return 0;
        }
        // one decimal digit, 0 to 9
        read = (read * 10ull) + (unsigned long long)(*walk - '0');
    }
    if ((read < least) || (read > maximum))
    {
        return 0;
    }
    *value = read;
    return 1;
}

int main(int count, char **arguments)
{
    char line_buffer[SIM_LINE_CAPACITY];
    SimResults results;
    sim_open(&results, line_buffer);
    unsigned long long length = OMEGA_COMPUTER_LENGTH_DEFAULT;
    unsigned long long deepest = OMEGA_COMPUTER_DEPTH_DEFAULT;
    unsigned long long budget = OMEGA_COMPUTER_STEPS_DEFAULT;
    const int understood =
        ((count < 2) || omega_computer_request(arguments[1], 2ull, OMEGA_COMPUTER_LENGTH_MAX, &length)) &&
        ((count < 3) || omega_computer_request(arguments[2], 1ull, OMEGA_COMPUTER_DEPTH_MAX, &deepest)) &&
        ((count < 4) || omega_computer_request(arguments[3], 1ull, 1ull << 40u, &budget)) && (count <= 4);
    if (understood == 0)
    {
        scriptura_text(&results.line, "  usage: omega_computer [L, 2 to 40] [depth, 1 to 8] [steps a run]\n");
        sim_check(&results, 0, "the request names its length, its depth and its steps");
        return sim_close(&results, "omega computer");
    }
    // the request's values are at most 40 and 8
    const unsigned int maximum = (unsigned int)length;
    const unsigned int depths = (unsigned int)deepest;

    // 1. U, and Tromp's test at every depth
    const std::string universal_code = s_omega_computer_universal;
    std::vector<int> universal;
    size_t universal_at = 0u;
    const int universal_closed =
        omega_computer_parse(universal_code, &universal_at, 0, universal) && (universal_at == universal_code.size());
    std::vector<int> delimit;
    size_t delimit_at = 0u;
    const std::string delimit_code = s_omega_computer_delimit;
    const int delimit_closed =
        omega_computer_parse(delimit_code, &delimit_at, 0, delimit) && (delimit_at == delimit_code.size());
    scriptura_text(&results.line, "  U, Tromp's universal machine: ");
    scriptura_decimal(&results.line, universal_code.size(), 1u);
    scriptura_text(&results.line, " bits, ");
    scriptura_decimal(&results.line, universal.size(), 1u);
    scriptura_text(&results.line, " tokens; delimit: ");
    scriptura_decimal(&results.line, delimit_code.size(), 1u);
    scriptura_text(&results.line, " bits\n");
    sim_check(&results,
              universal_closed && (universal_code.size() == 190u) && (omega_computer_code(universal) == universal_code),
              "U is one closed term of 190 bits, and its code reads back to itself");
    sim_flush(&results);
    OmegaComputerMachine machine;
    omega_computer_machine_open(&machine, universal);
    machine.step_budget = budget;
    std::vector<int> expected;
    omega_computer_list_tokens(s_omega_computer_delimit_output, expected);
    std::vector<int> normal;
    int tromp_ok = delimit_closed;
    scriptura_text(&results.line,
                   "  Tromp's test, delimit then 1111000111001: depth, fate, beta steps, and the list\n");
    for (unsigned int depth = 0u; depth <= depths; depth += 1u)
    {
        const OmegaComputerFate fate =
            omega_computer_run(&machine, delimit, s_omega_computer_delimit_input, depth, universal_code, normal);
        const int ok = (fate == OMEGA_COMPUTER_HALTS) && (normal == expected);
        tromp_ok = tromp_ok && ok;
        scriptura_text(&results.line, "    ");
        scriptura_decimal(&results.line, depth, 1u);
        scriptura_text(&results.line, (fate == OMEGA_COMPUTER_HALTS) ? "  halts  " : "  does not halt  ");
        scriptura_decimal(&results.line, machine.steps, 1u);
        scriptura_text(&results.line, "  cells ");
        scriptura_decimal(&results.line, machine.thunks.size() + machine.environments.size() + machine.spines.size(),
                          1u);
        scriptura_text(&results.line, (ok != 0) ? "  11010\n" : "  NOT 11010\n");
        sim_flush(&results);
    }
    std::vector<int> rewritten;
    unsigned long long rewrite_taken = 0ull;
    const OmegaComputerFate delimit_direct =
        omega_computer_direct(delimit, s_omega_computer_delimit_input, 1u << 20u, 1u << 19u, rewritten, &rewrite_taken);
    tromp_ok = tromp_ok && (delimit_direct == OMEGA_COMPUTER_HALTS) && (rewritten == expected);
    scriptura_text(&results.line, "    the rewriting, directly: fate ");
    scriptura_decimal(&results.line, (unsigned long long)delimit_direct, 1u);
    scriptura_text(&results.line, ", ");
    scriptura_decimal(&results.line, rewrite_taken, 1u);
    scriptura_text(&results.line, " steps, ");
    scriptura_decimal(&results.line, rewritten.size(), 1u);
    scriptura_text(&results.line, " tokens\n");
    sim_check(
        &results, tromp_ok,
        "U reading delimit and 1111000111001 gives the list 11010 at every depth, and the rewriting gives it directly");
    // diagnostic: normal order rewriting of U nested, its steps and its largest live term
    {
        std::vector<int> identity;
        identity.push_back(OMEGA_COMPUTER_LAMBDA);
        identity.push_back(1);
        const std::vector<int> *const tried[2] = {&identity, &delimit};
        const char *const inputs[2] = {"", s_omega_computer_delimit_input};
        for (unsigned int which = 0u; which < 2u; which += 1u)
        {
            for (unsigned int depth = 1u; depth <= 2u; depth += 1u)
            {
                std::string bits;
                for (unsigned int copy = 1u; copy < depth; copy += 1u)
                {
                    bits += universal_code;
                }
                bits += omega_computer_code(*tried[which]);
                bits += inputs[which];
                std::vector<int> nested;
                nested.push_back(OMEGA_COMPUTER_APPLY);
                nested.insert(nested.end(), universal.begin(), universal.end());
                omega_computer_list_tokens(bits, nested);
                const size_t start = nested.size();
                unsigned long long nested_taken = 0ull;
                const OmegaComputerFate nested_fate =
                    omega_computer_rewrite(nested, 1u << 18u, 1u << 17u, &nested_taken);
                scriptura_text(&results.line, "    rewriting ");
                scriptura_text(&results.line, (which == 0u) ? "identity" : "delimit");
                scriptura_text(&results.line, " depth ");
                scriptura_decimal(&results.line, depth, 1u);
                scriptura_text(&results.line, ": fate ");
                scriptura_decimal(&results.line, (unsigned long long)nested_fate, 1u);
                scriptura_text(&results.line, ", steps ");
                scriptura_decimal(&results.line, nested_taken, 1u);
                scriptura_text(&results.line, ", start ");
                scriptura_decimal(&results.line, start, 1u);
                scriptura_text(&results.line, " tokens, peak ");
                scriptura_decimal(&results.line, s_omega_computer_peak, 1u);
                scriptura_text(&results.line, " tokens\n");
                sim_flush(&results);
            }
        }
    }

    // 2 to 4. every closed M through L bits, run on nil at every depth
    OmegaComputerCounts counts;
    omega_computer_count_all(&counts, maximum);
    std::vector<unsigned long long> halted(depths + 1u, 0ull);
    std::vector<unsigned long long> looped(depths + 1u, 0ull);
    std::vector<unsigned long long> open(depths + 1u, 0ull);
    std::vector<unsigned long long> grew(depths + 1u, 0ull);
    std::vector<unsigned long long> halted_mass(depths + 1u, 0ull);
    std::vector<unsigned long long> steps_total(depths + 1u, 0ull);
    unsigned long long proven_mass = 0ull;
    unsigned long long programs = 0ull;
    unsigned long long direct_halted = 0ull;
    unsigned long long direct_proven = 0ull;
    unsigned long long agree_direct = 0ull;
    unsigned long long lazy_missed = 0ull;
    unsigned long long settled_everywhere = 0ull;
    unsigned long long contradictions = 0ull;
    unsigned long long unnested = 0ull;
    std::vector<unsigned long long> depth_steps(depths + 1u, 0ull);
    std::vector<OmegaComputerFate> fates(depths + 1u, OMEGA_COMPUTER_OPEN);
    std::vector<std::vector<int>> normals(depths + 1u);
    for (unsigned int bits = 2u; bits <= maximum; bits += 1u)
    {
        const unsigned long long terms = omega_computer_count(&counts, bits, 0u);
        const unsigned long long mass = 1ull << (maximum - bits);
        for (unsigned long long index = 0ull; index < terms; index += 1ull)
        {
            std::vector<int> program;
            omega_computer_unrank(&counts, bits, 0u, index, program);
            programs += 1ull;
            unsigned long long taken = 0ull;
            std::vector<int> direct_normal;
            const OmegaComputerFate direct = omega_computer_direct(
                program, "", OMEGA_COMPUTER_REWRITE_STEPS, OMEGA_COMPUTER_REWRITE_TOKENS, direct_normal, &taken);
            const int proven_by_rewriting = (direct == OMEGA_COMPUTER_LOOPS) || (direct == OMEGA_COMPUTER_DIVERGES);
            machine.step_budget =
                (proven_by_rewriting && (budget > OMEGA_COMPUTER_NEVER_STEPS)) ? OMEGA_COMPUTER_NEVER_STEPS : budget;
            for (unsigned int depth = 0u; depth <= depths; depth += 1u)
            {
                fates[depth] = omega_computer_run(&machine, program, "", depth, universal_code, normals[depth]);
                depth_steps[depth] = machine.steps;
            }
            // the direct run halts where the rewriting or the lazy machine at depth 0 halts, and never halts where
            // either proves it
            const int rewrite_halts = direct == OMEGA_COMPUTER_HALTS;
            const int rewrite_never = (direct == OMEGA_COMPUTER_LOOPS) || (direct == OMEGA_COMPUTER_DIVERGES);
            const std::vector<int> &reference = rewrite_halts ? direct_normal : normals[0];
            const int reference_halts = rewrite_halts || (fates[0] == OMEGA_COMPUTER_HALTS);
            int never = rewrite_never;
            for (unsigned int depth = 0u; depth <= depths; depth += 1u)
            {
                never = never || (fates[depth] == OMEGA_COMPUTER_LOOPS);
            }
            if (rewrite_halts && (fates[0] == OMEGA_COMPUTER_HALTS))
            {
                agree_direct += (direct_normal == normals[0]) ? 1ull : 0ull;
                contradictions += (direct_normal == normals[0]) ? 0ull : 1ull;
            }
            lazy_missed += (rewrite_halts && (fates[0] != OMEGA_COMPUTER_HALTS)) ? 1ull : 0ull;
            direct_halted += (reference_halts != 0) ? 1ull : 0ull;
            direct_proven += (never != 0) ? 1ull : 0ull;
            contradictions += ((reference_halts != 0) && (never != 0)) ? 1ull : 0ull;
            proven_mass += (never != 0) ? mass : 0ull;
            int everywhere = reference_halts;
            for (unsigned int depth = 0u; depth <= depths; depth += 1u)
            {
                const int halts = (depth == 0u) ? reference_halts : (fates[depth] == OMEGA_COMPUTER_HALTS);
                if (halts != 0)
                {
                    halted[depth] += 1ull;
                    halted_mass[depth] += mass;
                    // a halt at any depth has the direct run's normal form, and no run proves it never halts
                    if ((depth > 0u) && (((reference_halts != 0) && (normals[depth] != reference)) || (never != 0)))
                    {
                        contradictions += 1ull;
                    }
                    // every M the inner machine finishes, the outer machine finished
                    if (depth > 0u)
                    {
                        const int outer = (depth == 1u) ? reference_halts : (fates[depth - 1u] == OMEGA_COMPUTER_HALTS);
                        unnested += (outer != 0) ? 0ull : 1ull;
                    }
                }
                else
                {
                    everywhere = 0;
                    const OmegaComputerFate fate = (depth == 0u) ? (rewrite_never ? direct : fates[0]) : fates[depth];
                    looped[depth] +=
                        ((fate == OMEGA_COMPUTER_LOOPS) || (fate == OMEGA_COMPUTER_DIVERGES)) ? 1ull : 0ull;
                    open[depth] += (fate == OMEGA_COMPUTER_OPEN) ? 1ull : 0ull;
                    grew[depth] += (fate == OMEGA_COMPUTER_GREW) ? 1ull : 0ull;
                }
            }
            if (everywhere != 0)
            {
                settled_everywhere += 1ull;
                for (unsigned int depth = 0u; depth <= depths; depth += 1u)
                {
                    steps_total[depth] += depth_steps[depth];
                }
            }
        }
    }

    // the mass of every code through L bits, closed or not, over 2^L; what it leaves of 1 bounds every longer code
    std::vector<unsigned long long> all_codes(maximum + 1u, 0ull);
    unsigned long long counted = 0ull;
    unsigned long long closed_mass = 0ull;
    for (unsigned int bits = 2u; bits <= maximum; bits += 1u)
    {
        unsigned long long codes = 1ull + all_codes[bits - 2u];
        for (unsigned int left = 2u; (left + 4u) <= bits; left += 1u)
        {
            codes += all_codes[left] * all_codes[bits - 2u - left];
        }
        all_codes[bits] = codes;
        counted += codes << (maximum - bits);
        closed_mass += omega_computer_count(&counts, bits, 0u) << (maximum - bits);
    }
    const unsigned long long total = 1ull << maximum;
    // the upper bound: everything but the proven non-halts and the codes through L that are not closed
    const unsigned long long upper = total - proven_mass - (counted - closed_mass);

    scriptura_text(&results.line, "  ");
    scriptura_decimal(&results.line, programs, 1u);
    scriptura_text(&results.line, " closed programs through ");
    scriptura_decimal(&results.line, maximum, 1u);
    scriptura_text(&results.line, " bits, run on nil; the direct run halts ");
    scriptura_decimal(&results.line, direct_halted, 1u);
    scriptura_text(&results.line, " and proves ");
    scriptura_decimal(&results.line, direct_proven, 1u);
    scriptura_text(&results.line, " never halt; the rewriting and the lazy machine agree on ");
    scriptura_decimal(&results.line, agree_direct, 1u);
    scriptura_text(&results.line, " normal forms\n  depth  halted  proven never  out of steps  outgrew  Omega_nil at "
                                  "least  proven bits  steps (settled everywhere)\n");
    unsigned long long previous_mass = 0ull;
    int nested = 1;
    for (unsigned int depth = 0u; depth <= depths; depth += 1u)
    {
        nested = nested && ((depth == 0u) || (halted_mass[depth] <= previous_mass));
        previous_mass = halted_mass[depth];
        scriptura_text(&results.line, "    ");
        scriptura_decimal(&results.line, depth, 1u);
        scriptura_text(&results.line, "  ");
        scriptura_decimal(&results.line, halted[depth], 1u);
        scriptura_text(&results.line, "  ");
        scriptura_decimal(&results.line, looped[depth], 1u);
        scriptura_text(&results.line, "  ");
        scriptura_decimal(&results.line, open[depth], 1u);
        scriptura_text(&results.line, "  ");
        scriptura_decimal(&results.line, grew[depth], 1u);
        scriptura_text(&results.line, "  ");
        omega_computer_binary(&results.line, halted_mass[depth], maximum);
        scriptura_text(&results.line, "  ");
        scriptura_decimal(&results.line, omega_computer_proven(halted_mass[depth], upper, maximum), 1u);
        scriptura_text(&results.line, "  ");
        scriptura_decimal(&results.line, steps_total[depth], 1u);
        if (depth > 0u)
        {
            scriptura_text(&results.line, " (x");
            sim_fraction_print(&results.line, steps_total[depth],
                               (steps_total[depth - 1u] == 0ull) ? 1ull : steps_total[depth - 1u], 2u);
            scriptura_character(&results.line, ')');
        }
        scriptura_character(&results.line, '\n');
        sim_flush(&results);
    }
    scriptura_text(&results.line, "  Omega_nil at most ");
    omega_computer_binary(&results.line, upper, maximum);
    scriptura_text(&results.line, " at every depth; ");
    scriptura_decimal(&results.line, settled_everywhere, 1u);
    scriptura_text(&results.line, " programs halt at every depth\n");
    sim_check(&results, contradictions == 0ull,
              "every normal form at every depth is the direct run's, token for token, and no run halts that any run "
              "proves never halts");
    sim_check(
        &results, (unnested == 0ull) && nested,
        "each depth's bracket holds the one outside it: every program the inner machine finishes, the outer finished");
    sim_check(&results, (lazy_missed == 0ull) && (agree_direct > 0ull),
              "the lazy machine reaches every normal form the rewriting reaches, run directly");
    return sim_close(&results, "omega computer");
}
