// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// chaitin_omega_main.cu: the terms printed and main
#include "chaitin_omega_internal.h"

// a term from its code, for the checks below
static std::vector<int> omega_term(const char *code)
{
    std::vector<int> term;
    size_t at = 0u;
    while (code[at] != '\0')
    {
        if (code[at] == '0')
        {
            term.push_back((code[at + 1u] == '0') ? OMEGA_LAMBDA : OMEGA_APPLY);
            at += 2u;
        }
        else
        {
            int index = 0;
            while (code[at] == '1')
            {
                index += 1;
                at += 1u;
            }
            term.push_back(index);
            at += 1u;
        }
    }
    return term;
}

static OmegaFate omega_fate_of(const char *code, unsigned int steps, unsigned int tokens)
{
    std::vector<int> term = omega_term(code);
    std::vector<int> next;
    std::vector<int> stored;
    unsigned int taken = 0u;
    return omega_run(term, next, stored, steps, tokens, &taken);
}

// the bits of a mass scaled by 2^64
static void omega_bits(ScripturaLine *line, const AnchorExactInteger *value, unsigned int bits)
{
    scriptura_text(line, "0.");
    for (unsigned int bit = 0u; bit < bits; bit += 1u)
    {
        const unsigned int place = 63u - bit;
        scriptura_character(line, (((value->limb[place / 32u] >> (place % 32u)) & 1u) != 0u) ? '1' : '0');
    }
}

// the mass sum of count[n] 2^-n scaled by 2^64, exactly
static void omega_dyadic(AnchorExactInteger *value, const unsigned long long *count, unsigned int length)
{
    anchor_exact_zero(value);
    for (unsigned int bits = 2u; bits <= length; bits += 1u)
    {
        AnchorExactInteger part;
        AnchorExactInteger scale;
        sim_exact_unsigned(&part, count[bits]);
        sim_exact_unsigned(&scale, 1ull << (64u - bits));
        AnchorExactInteger product;
        (void)sim_exact_product(&part, &scale, &product);
        (void)sim_exact_sum(value, &product, value);
    }
}

int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    static char line_buffer[SIM_LINE_CAPACITY];
    SimResults results;
    sim_open(&results, line_buffer);
    static OmegaCounts counts;
    // L alone runs on the engine, bounded by nothing. L, steps and tokens run the budgeted kernel on the device
    // ("cpu" after them: on the host), kept as the cross-check. "--ledger <path>" plans either run as jobs.
    counts.length = (argc > 1) ? (unsigned int)strtoul(argv[1], NULL, 10) : OMEGA_LENGTH_DEFAULT;
    const int budgeted = (argc > 2) && (argv[2][0] >= '0') && (argv[2][0] <= '9');
    counts.steps = budgeted ? (unsigned int)strtoul(argv[2], NULL, 10) : OMEGA_STEPS_DEFAULT;
    counts.tokens = (budgeted && (argc > 3)) ? (unsigned int)strtoul(argv[3], NULL, 10) : OMEGA_TOKENS_DEFAULT;
    const int on_engine = !budgeted;
    int on_device = budgeted;
    const char *ledger = NULL;
    for (int at = 2; at < argc; at += 1)
    {
        if (strcmp(argv[at], "cpu") == 0)
        {
            on_device = 0;
        }
        else if ((strcmp(argv[at], "--ledger") == 0) && ((at + 1) < argc))
        {
            at += 1;
            ledger = argv[at];
        }
    }
    if ((counts.length < 4u) || (counts.length > OMEGA_LENGTH_MAX))
    {
        scriptura_text(&results.line, "  the length must be from 4 to 60 bits\n");
        sim_flush(&results);
        return 2;
    }
    if ((on_device != 0) && ((counts.tokens < 64u) || (counts.tokens > 16383u)))
    {
        // the device holds a term, its indices and its spine ends in 16 bits, in buffers twice the token budget
        scriptura_text(&results.line, "  on the device the token budget must be from 64 to 16383\n");
        sim_flush(&results);
        return 2;
    }
    omega_count_all(&counts);

    // the enumeration is checked against an independent parse of every code
    int counted = 1;
    const unsigned int parsed_max = (counts.length < OMEGA_PARSED_MAX) ? counts.length : OMEGA_PARSED_MAX;
    for (unsigned int length = 2u; length <= parsed_max; length += 1u)
    {
        unsigned long long closed = 0ull;
        for (unsigned long long code = 0ull; code < (1ull << length); code += 1ull)
        {
            unsigned int at = 0u;
            closed += ((omega_parse(code, length, &at, 0u) != 0) && (at == length)) ? 1ull : 0ull;
        }
        counted = counted && (closed == omega_count(&counts, length, 0u));
    }
    sim_check(&results, counted, "the closed term counts equal a parse of every code through 22 bits");
    int ranked = 1;
    for (unsigned int length = 2u; (length <= 16u) && (length <= counts.length); length += 1u)
    {
        for (unsigned long long index = 0ull; index < omega_count(&counts, length, 0u); index += 1ull)
        {
            std::vector<int> term;
            omega_unrank(&counts, length, 0u, index, term);
            unsigned long long bits = 0ull;
            for (size_t at = 0u; at < term.size(); at += 1u)
            {
                bits += (term[at] <= 0) ? 2ull : ((unsigned long long)term[at] + 1ull);
            }
            ranked = ranked && (bits == length) && (omega_end(term.data(), 0u) == term.size());
        }
    }
    sim_check(&results, ranked, "every unranked term through 16 bits is one term of its length");
    // I, I I, omega omega, K I (omega omega), and (lambda x. x x x)(lambda x. x x x)
    sim_check(&results, omega_fate_of("0010", 64u, 256u) == OMEGA_HALTS, "the identity is a normal form");
    sim_check(&results, omega_fate_of("0100100010", 64u, 256u) == OMEGA_HALTS, "I I reduces to I");
    sim_check(&results, omega_fate_of("010001101000011010", 64u, 256u) == OMEGA_LOOPS,
              "omega omega is watched returning to itself");
    sim_check(&results, omega_fate_of("010100001100010010001101000011010", 64u, 256u) == OMEGA_HALTS,
              "K I (omega omega) halts, normal order dropping the loop");
    sim_check(&results, omega_fate_of("01000101101010000101101010", 1000000u, 4096u) == OMEGA_DIVERGES,
              "(x x x)(x x x) is proven to grow forever: it returns at its own head");

    // a run on the device is one tessera job. The kernel's run declares the count table it copies there, and the
    // engine's run its first round's pool; the daemon measures the buffers each grows to and keeps that peak under the
    // run's arguments
    const unsigned long long declared = (on_engine != 0) ? omega_engine_declared(&counts) : sizeof(counts.count);
    if (((on_engine != 0) || (on_device != 0)) && !sim_job_submit(&results, "chaitin_omega", argc, argv, declared))
    {
        return sim_close(&results, "chaitin_omega");
    }

    // every closed term of at most L bits, run on the device unless the host is asked for
    const unsigned int workers = (std::thread::hardware_concurrency() == 0u) ? 1u : std::thread::hardware_concurrency();
    static OmegaResults fates;
    unsigned int device_threads = 0u;
    unsigned long long host_runs = 0ull;
    unsigned long long jobs_run = 0ull;
    unsigned long long jobs_kept = 0ull;
    const std::chrono::steady_clock::time_point start = std::chrono::steady_clock::now();
    OmegaEngineReport engine_report;
    memset(&engine_report, 0, sizeof(engine_report));
    std::vector<OmegaSettled> crossed;
    if (on_engine != 0)
    {
        if (omega_engine(&results, &counts, ledger, &engine_report, &crossed, &fates) == 0)
        {
            return sim_close(&results, "chaitin_omega");
        }
    }
    else if (on_device != 0)
    {
        if (omega_device(&results, &counts, workers, ledger, &device_threads, &host_runs, &jobs_run, &jobs_kept,
                         &fates) == 0)
        {
            return sim_close(&results, "chaitin_omega");
        }
    }
    else
    {
        omega_host(&counts, counts.length, workers, &fates);
    }
    const double seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count();
    if (on_device != 0)
    {
        // the host's run of the same terms under the same budgets must give every fate and busy beaver alike
        const unsigned int cross = (counts.length < OMEGA_CROSS_MAX) ? counts.length : OMEGA_CROSS_MAX;
        static OmegaResults host;
        omega_host(&counts, cross, workers, &host);
        int alike = (host.contradictions == 0ull);
        for (unsigned int length = 2u; length <= cross; length += 1u)
        {
            for (unsigned int fate = 0u; fate < 6u; fate += 1u)
            {
                alike = alike && (host.fate[fate][length] == fates.fate[fate][length]);
            }
            alike = alike && (host.max_steps[length] == fates.max_steps[length]) &&
                    (host.max_bits[length] == fates.max_bits[length]) &&
                    ((host.fate[OMEGA_HALTS][length] == 0ull) ||
                     ((host.steps_champion[length] == fates.steps_champion[length]) &&
                      (host.bits_champion[length] == fates.bits_champion[length])));
        }
        sim_check(&results, alike,
                  "the device's fates and busy beavers, champions included, equal the host's through 30 bits");
    }
    if (on_engine != 0)
    {
        // every term the engine settled through 24 bits, run again by omega_run with steps enough to reach the step
        // the engine settled it at and no token budget: the same fate, and for a halt the same step and the same
        // normal form. A loop is held to its fate alone, and a term that grew, by the growth proof or parked as
        // outgrown, is not run again
        std::atomic<int> every(1);
        omega_engine_threads(crossed.size(), workers, [&crossed, &every](size_t first, size_t last) {
            std::vector<int> term;
            std::vector<int> next;
            std::vector<int> stored;
            int same = 1;
            for (size_t at = first; at < last; at += 1u)
            {
                const OmegaSettled *const one = &crossed[at];
                if (one->fate == OMEGA_GREW)
                {
                    continue;
                }
                term.clear();
                omega_unrank(&counts, one->length, 0u, one->index, term);
                unsigned int taken = 0u;
                const OmegaFate fate =
                    omega_run(term, next, stored, (unsigned int)one->steps + 1u, 0xFFFFFFFFu, &taken);
                same = same && ((int)fate == one->fate) &&
                       ((fate != OMEGA_HALTS) || ((taken == one->steps) && (omega_code_bits(term) == one->bits)));
            }
            if (same == 0)
            {
                every = 0;
            }
        });
        sim_check(
            &results, (every.load() != 0) && !crossed.empty(),
            "every term the engine settled through 24 bits, those that grew aside: omega_run gives the same fate, "
            "and for a halt the same step and the same normal form");
    }

    // the mass past L, counted
    std::vector<unsigned long long> all_down;
    std::vector<unsigned long long> all_up;
    std::vector<unsigned long long> closed_up;
    omega_all_mass(all_down, 0);
    omega_all_mass(all_up, 1);
    omega_closed_mass(all_up, closed_up);
    unsigned long long parsed = 0ull;
    for (unsigned int length = 2u; length <= OMEGA_COUNTED; length += 1u)
    {
        parsed += all_down[length];
    }
    unsigned long long remaining = OMEGA_ONE - parsed;
    for (unsigned int length = counts.length + 1u; length <= OMEGA_COUNTED; length += 1u)
    {
        remaining += closed_up[length];
    }
    sim_check(&results, parsed <= OMEGA_ONE, "the counted parse mass stays below 1");
    std::vector<unsigned long long> normal_down;
    omega_normal_mass(normal_down);
    unsigned long long normal_end = 0ull;
    int normal_within = 1;
    for (unsigned int length = 2u; length <= OMEGA_COUNTED; length += 1u)
    {
        normal_within = normal_within && (normal_down[length] <= closed_up[length]);
        normal_end += (length > counts.length) ? normal_down[length] : 0ull;
    }
    sim_check(&results, normal_within, "the normal form mass is within the closed mass at every length");

    AnchorExactInteger lower;
    AnchorExactInteger open;
    AnchorExactInteger upper;
    AnchorExactInteger tail;
    AnchorExactInteger four;
    AnchorExactInteger programs;
    // a halt is a normal form reached or a type found
    std::vector<unsigned long long> halted(counts.length + 1u, 0ull);
    std::vector<unsigned long long> unsettled(counts.length + 1u, 0ull);
    for (unsigned int length = 0u; length <= counts.length; length += 1u)
    {
        halted[length] = fates.fate[OMEGA_HALTS][length] + fates.fate[OMEGA_TYPED][length];
        unsettled[length] = fates.fate[OMEGA_OPEN][length] + fates.fate[OMEGA_GREW][length];
    }
    omega_dyadic(&lower, halted.data(), counts.length);
    sim_check(&results, fates.contradictions == 0ull,
              "no term proven to loop or to grow forever has a simple type (every typable term halts)");
    omega_dyadic(&open, unsettled.data(), counts.length);
    std::vector<unsigned long long> closed_counts(counts.length + 1u, 0ull);
    for (unsigned int length = 2u; length <= counts.length; length += 1u)
    {
        closed_counts[length] = omega_count(&counts, length, 0u);
    }
    omega_dyadic(&programs, closed_counts.data(), counts.length);
    // the fixed point's 2^-62 scaled to 2^-64
    sim_exact_unsigned(&tail, remaining);
    sim_exact_unsigned(&four, 4ull);
    (void)sim_exact_product(&tail, &four, &tail);
    (void)sim_exact_sum(&lower, &open, &upper);
    (void)sim_exact_sum(&upper, &tail, &upper);
    // the normal forms past L halt unrun
    AnchorExactInteger normal;
    sim_exact_unsigned(&normal, normal_end);
    (void)sim_exact_product(&normal, &four, &normal);
    (void)sim_exact_sum(&lower, &normal, &lower);
    sim_check(&results, (lower.sign > 0) && (anchor_exact_compare(&lower, &upper) < 0),
              "the bracket is proper: 0 < lower < upper");

    unsigned int shared = 0u;
    while (shared < 64u)
    {
        const unsigned int place = 63u - shared;
        const unsigned int low_bit = (lower.limb[place / 32u] >> (place % 32u)) & 1u;
        const unsigned int high_bit = (upper.limb[place / 32u] >> (place % 32u)) & 1u;
        if (low_bit != high_bit)
        {
            break;
        }
        shared += 1u;
    }

    unsigned long long totals[6] = {0ull, 0ull, 0ull, 0ull, 0ull, 0ull};
    for (unsigned int fate = 0u; fate < 6u; fate += 1u)
    {
        for (unsigned int length = 0u; length <= counts.length; length += 1u)
        {
            totals[fate] += fates.fate[fate][length];
        }
    }
    scriptura_text(&results.line, "  Chaitin's Omega for the binary lambda calculus, every closed term through ");
    scriptura_decimal(&results.line, counts.length, 1u);
    scriptura_text(&results.line, " bits (");
    if (on_engine != 0)
    {
        scriptura_text(&results.line, "no step or token budget, ");
    }
    else
    {
        scriptura_decimal(&results.line, counts.steps, 1u);
        scriptura_text(&results.line, " steps, ");
        scriptura_decimal(&results.line, counts.tokens, 1u);
        scriptura_text(&results.line, " tokens, ");
    }
    if (on_device != 0)
    {
        scriptura_decimal(&results.line, device_threads, 1u);
        scriptura_text(&results.line, " device threads, ");
        scriptura_decimal(&results.line, host_runs, 1u);
        scriptura_text(&results.line, " runs past the device's budgets ran on the host, ");
        scriptura_decimal(&results.line, jobs_run, 1u);
        scriptura_text(&results.line, " jobs run, ");
        scriptura_decimal(&results.line, jobs_kept, 1u);
        scriptura_text(&results.line, " from the ledger, ");
    }
    else if (on_engine != 0)
    {
        scriptura_text(&results.line, "on the device's record machine, ");
        scriptura_decimal(&results.line, engine_report.rounds, 1u);
        scriptura_text(&results.line, " rounds, ");
        scriptura_decimal(&results.line, engine_report.records, 1u);
        scriptura_text(&results.line, " records swept, ");
        scriptura_decimal(&results.line, engine_report.parked, 1u);
        scriptura_text(&results.line, " parked as outgrown, ");
    }
    else
    {
        scriptura_decimal(&results.line, workers, 1u);
        scriptura_text(&results.line, " host threads, ");
    }
    scriptura_decimal(&results.line, (unsigned long long)(seconds * 1000.0), 1u);
    scriptura_text(&results.line,
                   " ms)\n  length    closed      halts  typed halts     loops  grows forever  out of steps"
                   "  outgrew\n");
    for (unsigned int length = 2u; length <= counts.length; length += 1u)
    {
        scriptura_decimal_columns(&results.line, length, 8u);
        scriptura_decimal_columns(&results.line, omega_count(&counts, length, 0u), 10u);
        scriptura_decimal_columns(&results.line, fates.fate[OMEGA_HALTS][length], 11u);
        scriptura_decimal_columns(&results.line, fates.fate[OMEGA_TYPED][length], 13u);
        scriptura_decimal_columns(&results.line, fates.fate[OMEGA_LOOPS][length], 10u);
        scriptura_decimal_columns(&results.line, fates.fate[OMEGA_DIVERGES][length], 15u);
        scriptura_decimal_columns(&results.line, fates.fate[OMEGA_OPEN][length], 14u);
        scriptura_decimal_columns(&results.line, fates.fate[OMEGA_GREW][length], 9u);
        scriptura_character(&results.line, '\n');
    }
    scriptura_text(&results.line, "  terms run ");
    scriptura_decimal(&results.line, totals[0] + totals[1] + totals[2] + totals[3] + totals[4] + totals[5], 1u);
    scriptura_text(&results.line, ": halted ");
    scriptura_decimal(&results.line, totals[OMEGA_HALTS], 1u);
    scriptura_text(&results.line, ", proven to halt by a simple type ");
    scriptura_decimal(&results.line, totals[OMEGA_TYPED], 1u);
    scriptura_text(&results.line, ", proven to loop ");
    scriptura_decimal(&results.line, totals[OMEGA_LOOPS], 1u);
    scriptura_text(&results.line, ", proven to grow forever ");
    scriptura_decimal(&results.line, totals[OMEGA_DIVERGES], 1u);
    scriptura_text(&results.line, ", out of steps ");
    scriptura_decimal(&results.line, totals[OMEGA_OPEN], 1u);
    scriptura_text(&results.line, ", outgrew the space ");
    scriptura_decimal(&results.line, totals[OMEGA_GREW], 1u);
    scriptura_text(&results.line, "\n  program mass through L  ");
    omega_bits(&results.line, &programs, 64u);
    scriptura_text(&results.line, "\n  normal forms past L     ");
    omega_bits(&results.line, &normal, 64u);
    scriptura_text(&results.line, "\n  Omega lower             ");
    omega_bits(&results.line, &lower, 64u);
    scriptura_text(&results.line, "\n  open mass               ");
    omega_bits(&results.line, &open, 64u);
    scriptura_text(&results.line, "\n  closed mass past L      ");
    omega_bits(&results.line, &tail, 64u);
    scriptura_text(&results.line, "\n  Omega upper             ");
    omega_bits(&results.line, &upper, 64u);
    scriptura_text(&results.line, "\n  Omega = 0.");
    for (unsigned int bit = 0u; bit < shared; bit += 1u)
    {
        const unsigned int place = 63u - bit;
        scriptura_character(&results.line, (((lower.limb[place / 32u] >> (place % 32u)) & 1u) != 0u) ? '1' : '0');
    }
    scriptura_text(&results.line, "...  (");
    scriptura_decimal(&results.line, shared, 1u);
    scriptura_text(&results.line, " bits proven)\n");
    sim_flush(&results);

    // the busy beaver table: a length with an open term reads "at least", since the open one may halt later
    // and larger
    scriptura_text(&results.line,
                   "\n  busy beavers of the halting terms (>= where a term of that length is still open)\n"
                   "  length  most steps  step champion                             BB lambda  normal form "
                   "champion\n");
    sim_flush(&results);
    for (unsigned int length = 2u; length <= counts.length; length += 1u)
    {
        if (fates.fate[OMEGA_HALTS][length] == 0ull)
        {
            continue;
        }
        // a typed halt proves a normal form exists without writing it. Its size is still unknown
        const int settled = ((unsettled[length] + fates.fate[OMEGA_TYPED][length]) == 0ull);
        scriptura_decimal_columns(&results.line, length, 8u);
        scriptura_text(&results.line, settled ? "    " : "  >=");
        scriptura_decimal_columns(&results.line, fates.max_steps[length], 8u);
        scriptura_text(&results.line, "  ");
        std::vector<int> champion;
        omega_unrank(&counts, length, 0u, fates.steps_champion[length], champion);
        omega_code_text(&results.line, champion);
        for (unsigned int pad = length; pad < 42u; pad += 1u)
        {
            scriptura_character(&results.line, ' ');
        }
        scriptura_text(&results.line, settled ? "  " : ">=");
        scriptura_decimal_columns(&results.line, fates.max_bits[length], 8u);
        scriptura_text(&results.line, "  ");
        champion.clear();
        omega_unrank(&counts, length, 0u, fates.bits_champion[length], champion);
        omega_code_text(&results.line, champion);
        scriptura_character(&results.line, '\n');
        sim_flush(&results);
    }
    // BusyBeaverWiki's BB lambda (OEIS A333479) from 4 through 33 bits; 0 where no closed term exists. The entries
    // equal the terms of OEIS's b-file for A333479 at 4 to 33. A row with a term still open
    // holds only a lower bound, and the published value is the true maximum. The two meeting means the run
    // reached the champion; past 33 the champions outgrow any space here (327686 bits at 34)
    static const unsigned long long published_max[34] = {
        0ull,  0ull,  0ull,  0ull,  4ull,  0ull,   6ull,   7ull,   8ull,   9ull,   10ull, 11ull,
        12ull, 13ull, 14ull, 15ull, 16ull, 17ull,  18ull,  19ull,  20ull,  22ull,  24ull, 26ull,
        30ull, 42ull, 52ull, 44ull, 58ull, 223ull, 160ull, 267ull, 298ull, 1812ull};
    int published = 1;
    int bounded = 1;
    for (unsigned int length = 4u; (length <= 33u) && (length <= counts.length); length += 1u)
    {
        const int settled = ((unsettled[length] + fates.fate[OMEGA_TYPED][length]) == 0ull);
        published = published && (fates.max_bits[length] == published_max[length]);
        bounded = bounded && (fates.max_bits[length] <= published_max[length]) &&
                  ((settled == 0) || (fates.max_bits[length] == published_max[length]));
    }
    // under any budgets: never past the true maximum, and on it wherever every term of the length halted
    sim_check(&results, bounded,
              "BB lambda is at most BusyBeaverWiki's (OEIS A333479) through 33 bits, and equal to it "
              "at every settled length");
    if ((counts.steps >= OMEGA_STEPS_DEFAULT) && (counts.tokens >= OMEGA_TOKENS_DEFAULT))
    {
        // the default budgets reach every champion through 33 bits, the 1812-bit normal form at 33 the largest
        sim_check(&results, published,
                  "BB lambda equals BusyBeaverWiki's (OEIS A333479) at every length through 33 bits");
    }
    return sim_close(&results, "chaitin_omega");
}
