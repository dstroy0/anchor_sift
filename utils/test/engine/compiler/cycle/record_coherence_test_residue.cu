// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// record_coherence_test_residue.cu: the residue table and main
#include "record_coherence_test_internal.h"

// A table step reads the low index_bits of its source's magnitude: -1 and 2^w - 1 read rows 1 and 2^b - 1. The
// table does not commute with the wrap. Indexed by the two's complement residue x mod 2^b, which the and with 2^b - 1
// gives never negative, it reads only bits the wrap to w >= b keeps and factors through every such projection: the
// residue table on x and on x wrapped to w read one row on every lane. A wrap narrower than b drops bits the residue
// reads and must break it on some lane, and the magnitude table must break at every width b or wider. Every read must
// equal the row the host's own two's complement word names.
static void coherence_residue_table(CoherenceResults *results)
{
    const unsigned int lanes = COHERENCE_TEST_LANES;
    const unsigned int rows = 1u << COHERENCE_TEST_TABLE_BITS;
    const unsigned long long row_mask = (unsigned long long)rows - 1ull;
    unsigned int *const atoms =
        (unsigned int *)calloc((size_t)lanes * COHERENCE_TEST_TABLE_INPUTS, sizeof(unsigned int));
    unsigned int *const values = (unsigned int *)calloc(rows, sizeof(unsigned int));
    CoherenceProgram *const program = (CoherenceProgram *)calloc(1u, sizeof(CoherenceProgram));
    if ((atoms == NULL) || (values == NULL) || (program == NULL))
    {
        coherence_check(results, 0, "the residue table lanes are held");
        free(atoms);
        free(values);
        free(program);
        return;
    }
    for (unsigned int row = 0u; row < rows; row += 1u)
    {
        values[row] = coherence_random() & ((1u << COHERENCE_TEST_TABLE_OUT_BITS) - 1u);
    }
    EngineRecordTable table;
    table.index_bits = COHERENCE_TEST_TABLE_BITS;
    table.out_bits = COHERENCE_TEST_TABLE_OUT_BITS;
    table.values = values;
    program->tables = &table;
    program->table_count = 1u;
    // x = f0 f1 + f2 reaches 48 bits. The wraps to 31 and 32 bits move it
    const unsigned int first = coherence_append(program, ENGINE_RECORD_FIELD_SIGNED, 0u, 0u);
    const unsigned int second = coherence_append(program, ENGINE_RECORD_FIELD_SIGNED, 1u, 0u);
    const unsigned int third = coherence_append(program, ENGINE_RECORD_FIELD_SIGNED, 2u, 0u);
    const unsigned int product = coherence_append(program, ENGINE_RECORD_PRODUCT, first, second);
    const unsigned int value = coherence_append(program, ENGINE_RECORD_SUM, product, third);
    const unsigned int mask = coherence_append(program, ENGINE_RECORD_CONSTANT, rows - 1u, 0u);
    const unsigned int residue = coherence_append(program, ENGINE_RECORD_AND, value, mask);
    coherence_output(program, coherence_append(program, ENGINE_RECORD_TABLE, residue, 0u));
    coherence_output(program, coherence_append(program, ENGINE_RECORD_TABLE, value, 0u));
    // for each width, the residue table on x wrapped, then the magnitude table on x wrapped where the wrap keeps b
    // bits: a table's index_bits may not pass its source's width
    unsigned int residue_output[COHERENCE_TEST_WIDTHS];
    unsigned int magnitude_output[COHERENCE_TEST_WIDTHS];
    for (unsigned int width = 0u; width < COHERENCE_TEST_WIDTHS; width += 1u)
    {
        const unsigned int bits = s_coherence_widths[width];
        const unsigned int wrapped = coherence_append(program, ENGINE_RECORD_WRAP, value, bits);
        const unsigned int wrapped_residue = coherence_append(program, ENGINE_RECORD_AND, wrapped, mask);
        residue_output[width] = program->output_count;
        coherence_output(program, coherence_append(program, ENGINE_RECORD_TABLE, wrapped_residue, 0u));
        magnitude_output[width] = program->output_count;
        if (bits >= COHERENCE_TEST_TABLE_BITS)
        {
            coherence_output(program, coherence_append(program, ENGINE_RECORD_TABLE, wrapped, 0u));
        }
    }
    CoherenceLoaded loaded;
    const int loads = coherence_load(program, COHERENCE_TEST_TABLE_INPUTS, &loaded);
    int words = 0;
    unsigned long long reckoned = 0ull;
    unsigned long long reckonings = 0ull;
    unsigned long long factored = 0ull;
    unsigned long long factorings = 0ull;
    unsigned int narrow_breaks = 0u;
    unsigned int magnitude_breaks[COHERENCE_TEST_WIDTHS] = {0u, 0u, 0u, 0u, 0u, 0u};
    if (loads != 0)
    {
        for (unsigned int at = 0u; at < lanes * COHERENCE_TEST_TABLE_INPUTS; at += 1u)
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
        words = host_ran && device_ran &&
                (memcmp(host_out, device_out, (size_t)lanes * out_limbs * sizeof(unsigned int)) == 0);
        for (unsigned int lane = 0u; host_ran && (lane < lanes); lane += 1u)
        {
            const unsigned int *const record = &device_out[(size_t)lane * out_limbs];
            const DeviceRecordStep *const steps = loaded.layout.step_table;
            const unsigned int *const atom = &atoms[lane * COHERENCE_TEST_TABLE_INPUTS];
            // the host's own x: two signed 24-bit fields multiplied stay far inside the word
            const long long native =
                (coherence_signed_input(atom[0]) * coherence_signed_input(atom[1])) + coherence_signed_input(atom[2]);
            const long long residue_row = coherence_take(record, &steps[program->outputs[0]]);
            const long long magnitude_row = coherence_take(record, &steps[program->outputs[1]]);
            reckonings += 2ull;
            // a signed word's two's complement: the cast keeps its bits, and the mask keeps the residue's
            reckoned += (residue_row == (long long)values[(unsigned long long)native & row_mask]) ? 1ull : 0ull;
            reckoned += (magnitude_row == (long long)values[coherence_magnitude(native) & row_mask]) ? 1ull : 0ull;
            for (unsigned int width = 0u; width < COHERENCE_TEST_WIDTHS; width += 1u)
            {
                const unsigned int bits = s_coherence_widths[width];
                // x as the wrap to w leaves it, from the host's word; the cast keeps the bits
                const long long kept = coherence_reduce((unsigned long long)native, bits);
                const long long wrapped_row = coherence_take(record, &steps[program->outputs[residue_output[width]]]);
                reckonings += 1ull;
                reckoned += (wrapped_row == (long long)values[(unsigned long long)kept & row_mask]) ? 1ull : 0ull;
                if (bits >= COHERENCE_TEST_TABLE_BITS)
                {
                    const long long wrapped_magnitude =
                        coherence_take(record, &steps[program->outputs[magnitude_output[width]]]);
                    factorings += 1ull;
                    factored += (wrapped_row == residue_row) ? 1ull : 0ull;
                    reckonings += 1ull;
                    reckoned +=
                        (wrapped_magnitude == (long long)values[coherence_magnitude(kept) & row_mask]) ? 1ull : 0ull;
                    magnitude_breaks[width] += (wrapped_magnitude != magnitude_row) ? 1u : 0u;
                }
                else
                {
                    narrow_breaks += (wrapped_row != residue_row) ? 1u : 0u;
                }
            }
        }
        free(host_out);
        free(device_out);
        coherence_free(&loaded);
    }
    unsigned int magnitude_fewest = lanes;
    scriptura_text(&results->line, "  residue table: 2^");
    scriptura_decimal(&results->line, COHERENCE_TEST_TABLE_BITS, 1u);
    scriptura_text(&results->line, " rows on x = f0 f1 + f2; indexed by x mod 2^");
    scriptura_decimal(&results->line, COHERENCE_TEST_TABLE_BITS, 1u);
    scriptura_text(&results->line, " it reads x's row after the wrap to");
    for (unsigned int width = 0u; width < COHERENCE_TEST_WIDTHS; width += 1u)
    {
        if (s_coherence_widths[width] >= COHERENCE_TEST_TABLE_BITS)
        {
            scriptura_character(&results->line, ' ');
            scriptura_decimal(&results->line, s_coherence_widths[width], 1u);
            magnitude_fewest =
                (magnitude_breaks[width] < magnitude_fewest) ? magnitude_breaks[width] : magnitude_fewest;
        }
    }
    scriptura_text(&results->line, " bits on ");
    scriptura_decimal(&results->line, factored, 1u);
    scriptura_text(&results->line, " of ");
    scriptura_decimal(&results->line, factorings, 1u);
    scriptura_text(&results->line, " lane-widths and breaks narrower on ");
    scriptura_decimal(&results->line, narrow_breaks, 1u);
    scriptura_text(&results->line, "; indexed by |x| mod 2^");
    scriptura_decimal(&results->line, COHERENCE_TEST_TABLE_BITS, 1u);
    scriptura_text(&results->line, " it breaks at each of those widths on at least ");
    scriptura_decimal(&results->line, magnitude_fewest, 1u);
    scriptura_text(&results->line, " of ");
    scriptura_decimal(&results->line, lanes, 1u);
    scriptura_text(&results->line, " lanes; ");
    scriptura_decimal(&results->line, reckoned, 1u);
    scriptura_text(&results->line, " of ");
    scriptura_decimal(&results->line, reckonings, 1u);
    scriptura_text(&results->line, " reads are the host's row\n");
    coherence_check(results, loads != 0, "the residue table program encodes, lays out and loads");
    coherence_check(results, words, "the residue table program's device records equal the host's word for word");
    coherence_check(results, (reckonings != 0ull) && (reckoned == reckonings),
                    "every table read is the row of x mod 2^b in two's complement, or of |x| mod 2^b");
    coherence_check(results, (factorings != 0ull) && (factored == factorings),
                    "a table indexed by x mod 2^b factors through the wrap to every w >= b");
    coherence_check(results, narrow_breaks != 0u, "a wrap narrower than b breaks the residue table on some lane");
    coherence_check(results, magnitude_fewest != 0u,
                    "a table indexed by |x| mod 2^b breaks under the wrap at every width b or wider");
    free(atoms);
    free(values);
    free(program);
}

int main(int count, char **arguments)
{
    CoherenceResults results;
    results.checks = 0ull;
    results.failures = 0ull;
    results.line.capacity = COHERENCE_TEST_LINE;
    results.line.out = (char *)malloc((size_t)COHERENCE_TEST_LINE);
    results.line.at = 0ull;
    if (results.line.out == NULL)
    {
        return 2;
    }
    char job_capacity[SIM_LINE_CAPACITY];
    SimResults job;
    sim_open(&job, job_capacity);
    const int admitted = sim_job_submit(&job, "record_coherence_test", count, arguments, COHERENCE_TEST_DECLARED);
    if (admitted != 0)
    {
        coherence_programs(&results);
        coherence_broken(&results);
        coherence_odd_divisors(&results);
        coherence_orthogonal(&results);
        coherence_residue_table(&results);
    }
    sim_job_release(&job);
    sim_flush(&job);
    coherence_check(&results, (admitted != 0) && (job.failures == 0ull),
                    "tessera: the device's daemon admits the test's job and it releases");
    scriptura_text(&results.line, "  record coherence test: ");
    scriptura_decimal(&results.line, results.checks, 1u);
    scriptura_text(&results.line, " checks, ");
    scriptura_decimal(&results.line, results.failures, 1u);
    scriptura_text(&results.line, " failed\n");
    scriptura_write(&results.line, stdout);
    free(results.line.out);
    return (results.failures == 0ull) ? 0 : 1;
}
