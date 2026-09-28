// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// record_boundary_test_main.cu: redundancy and main
#include "record_boundary_test_internal.h"

// The redundant residue code on the boundary ("Redundancy" in two_crystals' Open). T is n to n and every crystal is
// legal. A corrupted crystal is another crystal and T^-1 returns other samples with no sign of it. The code carries
// each crystal coefficient c, shifted to y = c + 2^21 in [0, 2^22), as its residues modulo four odd primes, where two
// cover the range (2053 . 2063 >= 2^22) and two are redundant. The decoder, a record program, reconstructs y from all
// four by Garner's mixed radix: a value past the range is a corrupted residue caught (the syndrome). It then drops each
// modulus in turn: with one residue corrupted, only the reconstruction that drops it lands in the range. The code
// corrects one and detects two. Encoder (T then the residues), decoder and T^-1 run on the device and the host, word
// for word.
static void boundary_redundant(BoundaryResults *results)
{
    const unsigned int n = BOUNDARY_TEST_SAMPLES;
    const unsigned int crystals = BOUNDARY_TEST_CODE_CRYSTALS;
    const unsigned int coefficients = crystals * n;
    const long long shift = 1ll << (BOUNDARY_TEST_CODE_BITS - 1u);
    // the moduli are odd, pairwise prime and ascending, and the two that carry the value cover the legal range
    int moduli_valid = 1;
    for (unsigned int at = 0u; at < BOUNDARY_TEST_CODE_MODULI; at += 1u)
    {
        moduli_valid = moduli_valid && ((s_boundary_moduli[at] & 1u) != 0u) &&
                       (boundary_prime_below(s_boundary_moduli[at] + 1u) == s_boundary_moduli[at]) &&
                       ((at == 0u) || (s_boundary_moduli[at - 1u] < s_boundary_moduli[at]));
    }
    moduli_valid = moduli_valid && (((unsigned long long)s_boundary_moduli[0] * s_boundary_moduli[1]) >=
                                    (1ull << BOUNDARY_TEST_CODE_BITS));
    BoundaryProgram *const encoder = (BoundaryProgram *)calloc(1u, sizeof(BoundaryProgram));
    BoundaryProgram *const decoder = (BoundaryProgram *)calloc(1u, sizeof(BoundaryProgram));
    BoundaryProgram *const inverse = (BoundaryProgram *)calloc(1u, sizeof(BoundaryProgram));
    BoundaryTower *const tower = (BoundaryTower *)calloc(1u, sizeof(BoundaryTower));
    BoundaryTower *const back = (BoundaryTower *)calloc(1u, sizeof(BoundaryTower));
    if ((encoder == NULL) || (decoder == NULL) || (inverse == NULL) || (tower == NULL) || (back == NULL))
    {
        boundary_check(results, 0, "the redundant residue code is held");
        free(encoder);
        free(decoder);
        free(inverse);
        free(tower);
        free(back);
        return;
    }
    // the encoder: T over the samples, then each coefficient's residues, coefficient by coefficient
    for (unsigned int at = 0u; at < n; at += 1u)
    {
        tower->low[0][at] = boundary_append(encoder, ENGINE_RECORD_FIELD_SIGNED, at, 0u);
    }
    boundary_forward(encoder, tower, BOUNDARY_TEST_SAMPLES, BOUNDARY_TEST_LEVELS);
    // the shift is 2^21, which fits the constant's word
    const unsigned int encoder_shift = boundary_append(encoder, ENGINE_RECORD_CONSTANT, (unsigned int)shift, 0u);
    unsigned int encoder_moduli[BOUNDARY_TEST_CODE_MODULI];
    for (unsigned int at = 0u; at < BOUNDARY_TEST_CODE_MODULI; at += 1u)
    {
        encoder_moduli[at] = boundary_append(encoder, ENGINE_RECORD_CONSTANT, s_boundary_moduli[at], 0u);
    }
    for (unsigned int at = 0u; at < n; at += 1u)
    {
        const unsigned int shifted = boundary_append(encoder, ENGINE_RECORD_SUM, tower->crystal[at], encoder_shift);
        for (unsigned int modulus = 0u; modulus < BOUNDARY_TEST_CODE_MODULI; modulus += 1u)
        {
            boundary_output(encoder,
                            boundary_append(encoder, ENGINE_RECORD_REMAINDER, shifted, encoder_moduli[modulus]));
        }
    }
    // the decoder, one coefficient a lane: the information residues alone, the syndrome, the reconstructions in the
    // range, and the corrected coefficient
    unsigned int residue[BOUNDARY_TEST_CODE_MODULI];
    for (unsigned int at = 0u; at < BOUNDARY_TEST_CODE_MODULI; at += 1u)
    {
        residue[at] = boundary_append(decoder, ENGINE_RECORD_FIELD, at, 0u);
    }
    const unsigned int range = boundary_append(decoder, ENGINE_RECORD_CONSTANT, 1u << BOUNDARY_TEST_CODE_BITS, 0u);
    const unsigned int decoder_shift = boundary_append(decoder, ENGINE_RECORD_CONSTANT, (unsigned int)shift, 0u);
    const unsigned int zero = boundary_append(decoder, ENGINE_RECORD_CONSTANT, 0u, 0u);
    const unsigned int one = boundary_append(decoder, ENGINE_RECORD_CONSTANT, 1u, 0u);
    const unsigned int every[BOUNDARY_TEST_CODE_MODULI] = {0u, 1u, 2u, 3u};
    const unsigned int plain = boundary_code_garner(decoder, residue, every, BOUNDARY_TEST_CODE_NEEDED);
    boundary_output(decoder, boundary_append(decoder, ENGINE_RECORD_DIFFERENCE, plain, decoder_shift));
    const unsigned int full = boundary_code_garner(decoder, residue, every, BOUNDARY_TEST_CODE_MODULI);
    boundary_output(decoder, boundary_code_outside(decoder, full, range, zero));
    unsigned int weighted = zero;
    unsigned int inside_count = zero;
    for (unsigned int dropped = 0u; dropped < BOUNDARY_TEST_CODE_MODULI; dropped += 1u)
    {
        unsigned int kept[BOUNDARY_TEST_CODE_MODULI - 1u];
        unsigned int count = 0u;
        for (unsigned int at = 0u; at < BOUNDARY_TEST_CODE_MODULI; at += 1u)
        {
            if (at != dropped)
            {
                kept[count] = at;
                count += 1u;
            }
        }
        const unsigned int candidate = boundary_code_garner(decoder, residue, kept, count);
        const unsigned int inside = boundary_append(decoder, ENGINE_RECORD_DIFFERENCE, one,
                                                    boundary_code_outside(decoder, candidate, range, zero));
        weighted = boundary_append(decoder, ENGINE_RECORD_SUM, weighted,
                                   boundary_append(decoder, ENGINE_RECORD_PRODUCT, inside, candidate));
        inside_count = boundary_append(decoder, ENGINE_RECORD_SUM, inside_count, inside);
    }
    boundary_output(decoder, inside_count);
    // the mean of the reconstructions in the range, the count held at one or more so no lane divides by zero
    const unsigned int none = boundary_append(decoder, ENGINE_RECORD_DIFFERENCE, one,
                                              boundary_append(decoder, ENGINE_RECORD_COMPARE, inside_count, zero));
    const unsigned int divisor = boundary_append(decoder, ENGINE_RECORD_SUM, inside_count, none);
    const unsigned int corrected = boundary_append(decoder, ENGINE_RECORD_QUOTIENT, weighted, divisor);
    boundary_output(decoder, boundary_append(decoder, ENGINE_RECORD_DIFFERENCE, corrected, decoder_shift));
    // T^-1 over a crystal's fields
    unsigned int crystal_fields[BOUNDARY_TEST_SAMPLES];
    for (unsigned int at = 0u; at < n; at += 1u)
    {
        crystal_fields[at] = boundary_append(inverse, ENGINE_RECORD_FIELD_SIGNED, at, 0u);
    }
    boundary_inverse(inverse, crystal_fields, NULL, NULL, back, BOUNDARY_TEST_SAMPLES, BOUNDARY_TEST_LEVELS);
    for (unsigned int at = 0u; at < n; at += 1u)
    {
        boundary_output(inverse, back->low[0][at]);
    }
    BoundaryLoaded encoder_loaded;
    BoundaryLoaded decoder_loaded;
    BoundaryLoaded inverse_loaded;
    const int encoder_loads = boundary_load(encoder, n, &encoder_loaded);
    const int decoder_loads =
        (encoder_loads != 0) && (boundary_load(decoder, BOUNDARY_TEST_CODE_MODULI, &decoder_loaded) != 0);
    const int loads = (decoder_loads != 0) && (boundary_load(inverse, n, &inverse_loaded) != 0);
    boundary_check(results, loads,
                   "the code's encoder (T then the residues), decoder and T^-1 encode, lay out and load");
    if (loads == 0)
    {
        if (decoder_loads != 0)
        {
            boundary_free(&decoder_loaded);
        }
        if (encoder_loads != 0)
        {
            boundary_free(&encoder_loaded);
        }
        free(encoder);
        free(decoder);
        free(inverse);
        free(tower);
        free(back);
        return;
    }
    const unsigned int decoder_lanes = BOUNDARY_TEST_CODE_KINDS * coefficients;
    const unsigned int inverse_lanes = 2u * crystals;
    unsigned int *const samples = (unsigned int *)calloc((size_t)crystals * n, sizeof(unsigned int));
    long long *const crystal = (long long *)calloc((size_t)coefficients, sizeof(long long));
    unsigned int *const encoder_host =
        (unsigned int *)calloc((size_t)crystals * encoder_loaded.layout.out_limbs, sizeof(unsigned int));
    unsigned int *const encoder_device =
        (unsigned int *)calloc((size_t)crystals * encoder_loaded.layout.out_limbs, sizeof(unsigned int));
    unsigned int *const words =
        (unsigned int *)calloc((size_t)decoder_lanes * BOUNDARY_TEST_CODE_MODULI, sizeof(unsigned int));
    // which residues each decoder lane had corrupted, one bit a modulus
    unsigned char *const hit = (unsigned char *)calloc(decoder_lanes, sizeof(unsigned char));
    unsigned int *const decoder_host =
        (unsigned int *)calloc((size_t)decoder_lanes * decoder_loaded.layout.out_limbs, sizeof(unsigned int));
    unsigned int *const decoder_device =
        (unsigned int *)calloc((size_t)decoder_lanes * decoder_loaded.layout.out_limbs, sizeof(unsigned int));
    unsigned int *const rebuilt = (unsigned int *)calloc((size_t)inverse_lanes * n, sizeof(unsigned int));
    unsigned int *const inverse_host =
        (unsigned int *)calloc((size_t)inverse_lanes * inverse_loaded.layout.out_limbs, sizeof(unsigned int));
    unsigned int *const inverse_device =
        (unsigned int *)calloc((size_t)inverse_lanes * inverse_loaded.layout.out_limbs, sizeof(unsigned int));
    const int buffers = (samples != NULL) && (crystal != NULL) && (encoder_host != NULL) && (encoder_device != NULL) &&
                        (words != NULL) && (hit != NULL) && (decoder_host != NULL) && (decoder_device != NULL) &&
                        (rebuilt != NULL) && (inverse_host != NULL) && (inverse_device != NULL);
    const long long sample_half = 1ll << (BOUNDARY_TEST_CODE_SAMPLE_BITS - 1u);
    for (unsigned int at = 0u; (buffers != 0) && (at < (crystals * n)); at += 1u)
    {
        const long long value =
            (long long)(boundary_random() & ((1u << BOUNDARY_TEST_CODE_SAMPLE_BITS) - 1u)) - sample_half;
        samples[at] = boundary_word(value);
    }
    const int encoded = (buffers != 0) &&
                        (boundary_run(&encoder_loaded, samples, crystals, encoder_host, encoder_device) != 0) &&
                        boundary_narrow_enough(&encoder_loaded, encoder);
    // the host's T gives each coefficient; it must lie in the legal range, and the encoder's residues must be its
    unsigned int in_range = 0u;
    unsigned int residues_right = 0u;
    for (unsigned int lane = 0u; (encoded != 0) && (lane < crystals); lane += 1u)
    {
        long long in[BOUNDARY_TEST_SAMPLES];
        for (unsigned int at = 0u; at < n; at += 1u)
        {
            in[at] = boundary_field(samples[((size_t)lane * n) + at]);
        }
        boundary_host_forward(in, &crystal[(size_t)lane * n]);
        const unsigned int *const record = &encoder_device[(size_t)lane * encoder_loaded.layout.out_limbs];
        for (unsigned int at = 0u; at < n; at += 1u)
        {
            const long long value = crystal[((size_t)lane * n) + at];
            in_range += ((value >= -shift) && (value < shift)) ? 1u : 0u;
            int right = 1;
            for (unsigned int modulus = 0u; modulus < BOUNDARY_TEST_CODE_MODULI; modulus += 1u)
            {
                const long long read = boundary_read(
                    record,
                    &encoder_loaded.layout.step_table[encoder->outputs[(at * BOUNDARY_TEST_CODE_MODULI) + modulus]]);
                right = right && (read == ((value + shift) % (long long)s_boundary_moduli[modulus]));
                // the kinds share the clean residues, which a corruption then changes; a residue is below 2^12
                for (unsigned int kind = 0u; kind < BOUNDARY_TEST_CODE_KINDS; kind += 1u)
                {
                    const size_t place = ((size_t)kind * coefficients) + ((size_t)lane * n) + at;
                    words[(place * BOUNDARY_TEST_CODE_MODULI) + modulus] = (unsigned int)read;
                }
            }
            residues_right += (right != 0) ? 1u : 0u;
        }
    }
    // corrupt half the coefficients: one residue in the second kind, two distinct residues in the third, each moved to
    // another value below its modulus
    unsigned int corrupted[BOUNDARY_TEST_CODE_KINDS] = {0u, 0u, 0u};
    for (unsigned int kind = 1u; (encoded != 0) && (kind < BOUNDARY_TEST_CODE_KINDS); kind += 1u)
    {
        for (unsigned int at = 0u; at < coefficients; at += 1u)
        {
            const size_t place = ((size_t)kind * coefficients) + at;
            if ((boundary_random() & 1u) == 0u)
            {
                continue;
            }
            const unsigned int first = boundary_random() % BOUNDARY_TEST_CODE_MODULI;
            const unsigned int second =
                (first + 1u + (boundary_random() % (BOUNDARY_TEST_CODE_MODULI - 1u))) % BOUNDARY_TEST_CODE_MODULI;
            const unsigned int moved[2] = {first, second};
            for (unsigned int which = 0u; which < kind; which += 1u)
            {
                const unsigned int modulus = s_boundary_moduli[moved[which]];
                unsigned int *const word = &words[(place * BOUNDARY_TEST_CODE_MODULI) + moved[which]];
                *word = (*word + 1u + (boundary_random() % (modulus - 1u))) % modulus;
                hit[place] |= (unsigned char)(1u << moved[which]);
            }
            corrupted[kind] += 1u;
        }
    }
    const int decoded = (encoded != 0) &&
                        (boundary_run(&decoder_loaded, words, decoder_lanes, decoder_host, decoder_device) != 0) &&
                        boundary_narrow_enough(&decoder_loaded, decoder);
    unsigned int clean_right = 0u;
    unsigned int false_alarms = 0u;
    unsigned int flagged_right[BOUNDARY_TEST_CODE_KINDS] = {0u, 0u, 0u};
    unsigned int corrected_right = 0u;
    unsigned int detected = 0u;
    unsigned int miscorrected = 0u;
    unsigned int plain_moved = 0u;
    for (unsigned int lane = 0u; (decoded != 0) && (lane < decoder_lanes); lane += 1u)
    {
        const unsigned int kind = lane / coefficients;
        const long long value = crystal[lane % coefficients];
        const unsigned int *const record = &decoder_device[(size_t)lane * decoder_loaded.layout.out_limbs];
        const DeviceRecordStep *const steps = decoder_loaded.layout.step_table;
        const long long plain_value = boundary_read(record, &steps[decoder->outputs[0]]);
        const long long syndrome = boundary_read(record, &steps[decoder->outputs[1]]);
        const long long inside = boundary_read(record, &steps[decoder->outputs[2]]);
        const long long corrected_value = boundary_read(record, &steps[decoder->outputs[3]]);
        const int struck = hit[lane] != 0u;
        flagged_right[kind] += ((syndrome == 1ll) == (struck != 0)) ? 1u : 0u;
        if (kind == 0u)
        {
            clean_right += ((plain_value == value) && (corrected_value == value) && (inside == 4ll)) ? 1u : 0u;
            false_alarms += (syndrome != 0ll) ? 1u : 0u;
        }
        else if (kind == 1u)
        {
            corrected_right += ((corrected_value == value) && (inside == (struck ? 1ll : 4ll))) ? 1u : 0u;
            plain_moved += (plain_value != value) ? 1u : 0u;
            // the corrected crystal and the information residues' crystal, for T^-1
            const unsigned int coefficient = lane % coefficients;
            rebuilt[coefficient] = boundary_word(corrected_value);
            rebuilt[coefficients + coefficient] = boundary_word(plain_value);
        }
        else
        {
            detected += ((struck != 0) && (syndrome == 1ll)) ? 1u : 0u;
            miscorrected += ((struck != 0) && (corrected_value != value)) ? 1u : 0u;
        }
    }
    const int inverted = (decoded != 0) &&
                         (boundary_run(&inverse_loaded, rebuilt, inverse_lanes, inverse_host, inverse_device) != 0) &&
                         boundary_narrow_enough(&inverse_loaded, inverse);
    unsigned int returned = 0u;
    unsigned int plain_mapped = 0u;
    unsigned int plain_other = 0u;
    unsigned int plain_right = 0u;
    for (unsigned int lane = 0u; (inverted != 0) && (lane < crystals); lane += 1u)
    {
        const unsigned int *const corrected_record = &inverse_device[(size_t)lane * inverse_loaded.layout.out_limbs];
        const unsigned int *const plain_record =
            &inverse_device[(size_t)(crystals + lane) * inverse_loaded.layout.out_limbs];
        long long plain_crystal[BOUNDARY_TEST_SAMPLES];
        long long plain_samples[BOUNDARY_TEST_SAMPLES];
        // an information residue struck in any of the lane's coefficients moves its crystal
        int information_struck = 0;
        for (unsigned int at = 0u; at < n; at += 1u)
        {
            plain_crystal[at] = boundary_field(rebuilt[coefficients + (lane * n) + at]);
            information_struck = information_struck || ((hit[coefficients + (lane * n) + at] & 3u) != 0u);
        }
        boundary_host_inverse(plain_crystal, plain_samples);
        int same = 1;
        int mapped = 1;
        int differs = 0;
        for (unsigned int at = 0u; at < n; at += 1u)
        {
            const DeviceRecordStep *const step = &inverse_loaded.layout.step_table[inverse->outputs[at]];
            const long long original = boundary_field(samples[((size_t)lane * n) + at]);
            const long long plain_sample = boundary_read(plain_record, step);
            same = same && (boundary_read(corrected_record, step) == original);
            mapped = mapped && (plain_sample == plain_samples[at]);
            differs = differs || (plain_sample != original);
        }
        returned += (same != 0) ? 1u : 0u;
        plain_mapped += (mapped != 0) ? 1u : 0u;
        plain_other += (differs != 0) ? 1u : 0u;
        plain_right += (differs == information_struck) ? 1u : 0u;
    }
    scriptura_text(&results->line, "  redundant residue code: moduli");
    for (unsigned int at = 0u; at < BOUNDARY_TEST_CODE_MODULI; at += 1u)
    {
        scriptura_character(&results->line, ' ');
        scriptura_decimal(&results->line, s_boundary_moduli[at], 1u);
    }
    scriptura_text(&results->line, ", the first two covering [-2^21, 2^21); ");
    scriptura_decimal(&results->line, crystals, 1u);
    scriptura_text(&results->line, " crystals of T over 16-bit samples, ");
    scriptura_decimal(&results->line, in_range, 1u);
    scriptura_text(&results->line, " of ");
    scriptura_decimal(&results->line, coefficients, 1u);
    scriptura_text(&results->line, " coefficients in the range, ");
    scriptura_decimal(&results->line, residues_right, 1u);
    scriptura_text(&results->line, " encoded right\n    clean: ");
    scriptura_decimal(&results->line, clean_right, 1u);
    scriptura_text(&results->line, " decode to their coefficient, ");
    scriptura_decimal(&results->line, false_alarms, 1u);
    scriptura_text(&results->line, " false alarms\n    one residue corrupted in ");
    scriptura_decimal(&results->line, corrupted[1], 1u);
    scriptura_text(&results->line, ": the syndrome is right on ");
    scriptura_decimal(&results->line, flagged_right[1], 1u);
    scriptura_text(&results->line, " and the coefficient corrected on ");
    scriptura_decimal(&results->line, corrected_right, 1u);
    scriptura_text(&results->line, " of ");
    scriptura_decimal(&results->line, coefficients, 1u);
    scriptura_text(&results->line, "; T^-1 of the corrected crystal returns the samples on ");
    scriptura_decimal(&results->line, returned, 1u);
    scriptura_text(&results->line, " of ");
    scriptura_decimal(&results->line, crystals, 1u);
    scriptura_text(&results->line, "\n    two residues corrupted in ");
    scriptura_decimal(&results->line, corrupted[2], 1u);
    scriptura_text(&results->line, ": detected on ");
    scriptura_decimal(&results->line, detected, 1u);
    scriptura_text(&results->line, ", the syndrome right on ");
    scriptura_decimal(&results->line, flagged_right[2], 1u);
    scriptura_text(&results->line, " of ");
    scriptura_decimal(&results->line, coefficients, 1u);
    scriptura_text(&results->line, "; the one-error correction misses ");
    scriptura_decimal(&results->line, miscorrected, 1u);
    scriptura_text(&results->line, " of them\n    without the code: the two information residues alone read ");
    scriptura_decimal(&results->line, plain_moved, 1u);
    scriptura_text(&results->line, " coefficients as another's, and T^-1 runs on all ");
    scriptura_decimal(&results->line, crystals, 1u);
    scriptura_text(&results->line, " crystals, returning other samples on ");
    scriptura_decimal(&results->line, plain_other, 1u);
    scriptura_text(&results->line, ", exactly where an information residue was struck on ");
    scriptura_decimal(&results->line, plain_right, 1u);
    scriptura_character(&results->line, '\n');
    boundary_check(results, moduli_valid,
                   "the moduli are odd primes, ascending, and the first two cover the range 2^22");
    boundary_check(results, (encoded != 0) && (decoded != 0) && (inverted != 0),
                   "encoder, decoder and T^-1 run on the host and the device, word for word");
    boundary_check(results, (in_range == coefficients) && (residues_right == coefficients),
                   "every coefficient of T lies in the legal range and the encoder's residues are its");
    boundary_check(results, (clean_right == coefficients) && (false_alarms == 0u),
                   "a clean codeword decodes to its coefficient with no false alarm");
    boundary_check(results, (corrupted[1] != 0u) && (flagged_right[1] == coefficients),
                   "the syndrome flags exactly the coefficients with a corrupted residue");
    boundary_check(results, corrected_right == coefficients, "one corrupted residue is corrected on every coefficient");
    boundary_check(results, returned == crystals, "T^-1 of the corrected crystal returns the samples exactly");
    boundary_check(results, (corrupted[2] != 0u) && (detected == corrupted[2]) && (flagged_right[2] == coefficients),
                   "two corrupted residues are detected on every coefficient");
    boundary_check(
        results, (plain_mapped == crystals) && (plain_other != 0u) && (plain_right == crystals),
        "without the code a corrupted crystal is another crystal: T^-1 returns other samples, no sign of it");
    free(samples);
    free(crystal);
    free(encoder_host);
    free(encoder_device);
    free(words);
    free(hit);
    free(decoder_host);
    free(decoder_device);
    free(rebuilt);
    free(inverse_host);
    free(inverse_device);
    boundary_free(&encoder_loaded);
    boundary_free(&decoder_loaded);
    boundary_free(&inverse_loaded);
    free(encoder);
    free(decoder);
    free(inverse);
    free(tower);
    free(back);
}

int main(int count, char **arguments)
{
    BoundaryResults results;
    results.checks = 0ull;
    results.failures = 0ull;
    results.line.capacity = BOUNDARY_TEST_LINE;
    results.line.out = (char *)malloc((size_t)BOUNDARY_TEST_LINE);
    results.line.at = 0ull;
    if (results.line.out == NULL)
    {
        return 2;
    }
    boundary_matrices();
    boundary_bands(&results);
    char job_capacity[SIM_LINE_CAPACITY];
    SimResults job;
    sim_open(&job, job_capacity);
    const int admitted = sim_job_submit(&job, "record_boundary_test", count, arguments, BOUNDARY_TEST_DECLARED);
    if (admitted != 0)
    {
        boundary_written(&results);
        boundary_read_off(&results);
        boundary_floors(&results);
        boundary_top(&results);
        boundary_counted(&results);
        boundary_redundant(&results);
    }
    sim_job_release(&job);
    sim_flush(&job);
    boundary_check(&results, (admitted != 0) && (job.failures == 0ull),
                   "tessera: the device's daemon admits the test's job and it releases");
    boundary_volume(&results);
    scriptura_text(&results.line, "  record boundary test: ");
    scriptura_decimal(&results.line, results.checks, 1u);
    scriptura_text(&results.line, " checks, ");
    scriptura_decimal(&results.line, results.failures, 1u);
    scriptura_text(&results.line, " failed\n");
    scriptura_write(&results.line, stdout);
    free(results.line.out);
    return (results.failures == 0ull) ? 0 : 1;
}
