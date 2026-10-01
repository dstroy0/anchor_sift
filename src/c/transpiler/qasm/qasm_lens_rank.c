// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// qasm_lens_rank.c: rows, rank, the clock, the seal and the read
#include "qasm_lens_internal.h"

static unsigned int qasm_lens_row_bit(const QasmLensRow *row, unsigned int column)
{
    return (row->word[column / 32u] >> (column % 32u)) & 1u;
}

static QasmLensRow qasm_lens_generator_row(const QasmLensState *table, unsigned int image, int lifted)
{
    QasmLensRow row;
    memset(&row, 0, sizeof(row));
    for (unsigned int word = 0u; word < QASM_LENS_STATE_WORDS; word += 1u)
    {
        row.word[word] = table[image].word[word] ^ table[0].word[word];
    }
    if (lifted != 0)
    {
        for (unsigned int index = 0u; index < (QASM_LENS_LIFT_BITS - QASM_LENS_RAW_BITS); index += 1u)
        {
            // the Python lift's pairing: bit index against bit (131 index + 17) mod 256, never itself
            const unsigned int partner = ((index * 131u) + 17u) & 255u;
            const unsigned int other = (partner == index) ? ((partner + 1u) & 255u) : partner;
            const unsigned int column = QASM_LENS_RAW_BITS + index;
            row.word[column / 32u] |= (qasm_lens_row_bit(&row, index) & qasm_lens_row_bit(&row, other))
                                      << (column % 32u);
        }
    }
    return row;
}

static void qasm_lens_basis_insert(QasmLensBasis *basis, QasmLensRow row, unsigned int columns)
{
    // a full basis spans every row: the rest reduce to zero and add no rank
    if (basis->rank == columns)
    {
        return;
    }
    for (unsigned int column = 0u; column < columns; column += 1u)
    {
        if (qasm_lens_row_bit(&row, column) != 0u)
        {
            if (basis->occupied[column] == 0u)
            {
                basis->pivot_row[column] = row;
                basis->occupied[column] = 1u;
                basis->rank += 1u;
                return;
            }
            for (unsigned int word = column / 32u; word < (columns / 32u); word += 1u)
            {
                row.word[word] ^= basis->pivot_row[column].word[word];
            }
        }
    }
}

static unsigned int qasm_lens_rank(const QasmLensState *forward_table, const QasmLensState *backward_table,
                                   unsigned int size, int lifted, QasmLensBasis *basis)
{
    memset(basis, 0, sizeof(*basis));
    const unsigned int columns = (lifted != 0) ? QASM_LENS_LIFT_BITS : QASM_LENS_RAW_BITS;
    const QasmLensState *const tables[2u] = {forward_table, backward_table};
    for (unsigned int strand = 0u; strand < 2u; strand += 1u)
    {
        for (unsigned int image = 1u; image < size; image += 1u)
        {
            qasm_lens_basis_insert(basis, qasm_lens_generator_row(tables[strand], image, lifted), columns);
        }
    }
    return basis->rank;
}

static int qasm_lens_clock_closes(const QasmLensRequest *request, const QasmLensState *anchor, const unsigned int *base)
{
    unsigned int schedule[QASM_LENS_ROUNDS_MAX];
    qasm_lens_schedule_expand(base, request->rounds, schedule);
    const QasmLensState chaining_input = qasm_lens_invert_from_state(anchor, schedule, request->middle, 0u);
    const QasmLensState returned = qasm_lens_forward_from_state(&chaining_input, schedule, 0u, request->middle);
    return memcmp(&returned, anchor, sizeof(QasmLensState)) == 0;
}

static unsigned int qasm_lens_curvature_vanish(const QasmLensState *table, unsigned int bits, QasmLensSplitMix *draws)
{
    // an aperture below 4 images counts every sample as vanished, as the Python's 1.0 does
    if ((1u << bits) < 4u)
    {
        return QASM_LENS_CURVATURE_SAMPLES;
    }
    unsigned int vanish = 0u;
    for (unsigned int sample = 0u; sample < QASM_LENS_CURVATURE_SAMPLES; sample += 1u)
    {
        const unsigned int origin = qasm_lens_splitmix_bits(draws, bits);
        const unsigned int first_step = qasm_lens_splitmix_bits(draws, bits);
        const unsigned int second_step = qasm_lens_splitmix_bits(draws, bits);
        unsigned int second_difference = 0u;
        for (unsigned int word = 0u; word < QASM_LENS_STATE_WORDS; word += 1u)
        {
            second_difference |= table[origin].word[word] ^ table[origin ^ first_step].word[word] ^
                                 table[origin ^ second_step].word[word] ^
                                 table[origin ^ first_step ^ second_step].word[word];
        }
        if (second_difference == 0u)
        {
            vanish += 1u;
        }
    }
    return vanish;
}

static int qasm_lens_state_order(const void *left, const void *right)
{
    return memcmp(left, right, sizeof(QasmLensState));
}

static unsigned long long qasm_lens_fiber_count(QasmLensState *table, unsigned int size)
{
    // sorts the table in place: the caller reads it no further
    qsort(table, size, sizeof(QasmLensState), qasm_lens_state_order);
    unsigned long long distinct = 1ull;
    for (unsigned int image = 1u; image < size; image += 1u)
    {
        if (memcmp(&table[image], &table[image - 1u], sizeof(QasmLensState)) != 0)
        {
            distinct += 1ull;
        }
    }
    return distinct;
}

static void qasm_lens_generator_bytes(const QasmLensState *table, unsigned int size, unsigned char *bytes,
                                      unsigned int first_generator)
{
    for (unsigned int image = 1u; image < size; image += 1u)
    {
        const size_t generator = first_generator + (image - 1u);
        unsigned char *const generator_slot = &bytes[generator * QASM_LENS_GENERATOR_BYTES];
        for (unsigned int word = 0u; word < QASM_LENS_STATE_WORDS; word += 1u)
        {
            const unsigned int value = table[image].word[word] ^ table[0].word[word];
            for (unsigned int byte = 0u; byte < 4u; byte += 1u)
            {
                // one byte of the word, masked to eight bits, which an unsigned char holds exactly
                generator_slot[(4u * word) + byte] = (unsigned char)((value >> (8u * byte)) & 0xFFu);
            }
        }
    }
}

static long qasm_lens_seal(const unsigned char *bytes, unsigned long long generators, unsigned char *signum,
                           EngineError *error)
{
    const ObsignatioSealRequest seal = {bytes, generators * QASM_LENS_GENERATOR_BYTES, signum, error};
    return obsignatio_seal(&seal);
}

static int qasm_lens_request_valid(const QasmLensRequest *request, EngineError *error)
{
    return QASM_CHECK((request->rounds <= QASM_LENS_ROUNDS_MAX) && (request->middle < request->rounds) &&
                          (request->forward_word < QASM_LENS_MESSAGE_WORDS) &&
                          (request->backward_word < QASM_LENS_MESSAGE_WORDS) && (request->bits <= QASM_LENS_BITS_MAX),
                      request, error);
}

long qasm_lens_read(const QasmLensRequest *request, QasmLensMeasurement *measurement, EngineError *error)
{
    if (error == NULL)
    {
        return QASM_ERROR;
    }
    if (!QASM_CHECK((request != NULL) && (measurement != NULL), request, error) ||
        !qasm_lens_request_valid(request, error))
    {
        return QASM_ERROR;
    }
    const unsigned int size = 1u << request->bits;
    const unsigned int generators = 2u * (size - 1u);
    QasmLensState *const forward_table = (QasmLensState *)calloc(size, sizeof(QasmLensState));
    QasmLensState *const backward_table = (QasmLensState *)calloc(size, sizeof(QasmLensState));
    unsigned char *const generator_bytes =
        (generators != 0u) ? (unsigned char *)calloc(generators, QASM_LENS_GENERATOR_BYTES) : NULL;
    QasmLensBasis *const basis = (QasmLensBasis *)calloc(1u, sizeof(QasmLensBasis));
    if (!QASM_HAD((forward_table != NULL) && (backward_table != NULL) &&
                      ((generators == 0u) || (generator_bytes != NULL)) && (basis != NULL),
                  request, error))
    {
        free(forward_table);
        free(backward_table);
        free(generator_bytes);
        free(basis);
        return QASM_ERROR;
    }
    QasmLensState anchor;
    unsigned int base[QASM_LENS_MESSAGE_WORDS];
    const QasmLensState target = qasm_lens_instance_draw(request, &anchor, base);
    qasm_lens_forward_field_table(request, &anchor, base, &target, forward_table);
    qasm_lens_backward_field_table(request, &anchor, base, backward_table);
    const unsigned int raw_rank = qasm_lens_rank(forward_table, backward_table, size, 0, basis);
    const unsigned int lift_rank = qasm_lens_rank(forward_table, backward_table, size, 1, basis);
    const int reversible = qasm_lens_clock_closes(request, &anchor, base);
    qasm_lens_generator_bytes(forward_table, size, generator_bytes, 0u);
    qasm_lens_generator_bytes(backward_table, size, generator_bytes, size - 1u);
    // the read is taken twice over the same generators, as the Python re-reads its witness root
    unsigned char root[ENGINE_SIGNUM_BYTES];
    unsigned char root_again[ENGINE_SIGNUM_BYTES];
    const int sealed = (qasm_lens_seal(generator_bytes, generators, root, error) == 0L) &&
                       (qasm_lens_seal(generator_bytes, generators, root_again, error) == 0L);
    QasmLensSplitMix forward_draws =
        qasm_lens_splitmix_start(request->seed, request->instance ^ QASM_LENS_FORWARD_SALT);
    QasmLensSplitMix backward_draws =
        qasm_lens_splitmix_start(request->seed, request->instance ^ QASM_LENS_BACKWARD_SALT);
    const unsigned int forward_vanish = qasm_lens_curvature_vanish(forward_table, request->bits, &forward_draws);
    const unsigned int backward_vanish = qasm_lens_curvature_vanish(backward_table, request->bits, &backward_draws);
    const unsigned long long forward_fiber = qasm_lens_fiber_count(forward_table, size);
    const unsigned long long backward_fiber = qasm_lens_fiber_count(backward_table, size);
    free(forward_table);
    free(backward_table);
    free(generator_bytes);
    free(basis);
    if (!sealed)
    {
        return QASM_ERROR;
    }
    measurement->raw_rank = raw_rank;
    // a rank over 256 columns is at most 256
    measurement->complement = QASM_LENS_RAW_BITS - raw_rank;
    // the lift keeps the raw columns. Its rank is at least the raw rank
    measurement->lift_extra_rank = lift_rank - raw_rank;
    measurement->forward_vanish = forward_vanish;
    measurement->backward_vanish = backward_vanish;
    measurement->forward_fiber = forward_fiber;
    measurement->backward_fiber = backward_fiber;
    measurement->reversible = reversible;
    measurement->root_stable = memcmp(root, root_again, ENGINE_SIGNUM_BYTES) == 0;
    memcpy(measurement->root, root, ENGINE_SIGNUM_BYTES);
    return 0L;
}

long qasm_lens_seal_check(const QasmLensRequest *request, unsigned char *clean, unsigned char *flipped,
                          EngineError *error)
{
    if (error == NULL)
    {
        return QASM_ERROR;
    }
    // the Python flips a bit of the first generator, which an empty aperture does not have
    if (!QASM_CHECK((request != NULL) && (clean != NULL) && (flipped != NULL), request, error) ||
        !qasm_lens_request_valid(request, error) || !QASM_CHECK(request->bits != 0u, request, error))
    {
        return QASM_ERROR;
    }
    const unsigned int size = 1u << request->bits;
    const unsigned int generators = size - 1u;
    QasmLensState *const table = (QasmLensState *)calloc(size, sizeof(QasmLensState));
    unsigned char *const generator_bytes = (unsigned char *)calloc(generators, QASM_LENS_GENERATOR_BYTES);
    if (!QASM_HAD((table != NULL) && (generator_bytes != NULL), request, error))
    {
        free(table);
        free(generator_bytes);
        return QASM_ERROR;
    }
    QasmLensState anchor;
    unsigned int base[QASM_LENS_MESSAGE_WORDS];
    const QasmLensState target = qasm_lens_instance_draw(request, &anchor, base);
    qasm_lens_forward_field_table(request, &anchor, base, &target, table);
    qasm_lens_generator_bytes(table, size, generator_bytes, 0u);
    unsigned char clean_root[ENGINE_SIGNUM_BYTES];
    unsigned char flipped_root[ENGINE_SIGNUM_BYTES];
    const int clean_sealed = qasm_lens_seal(generator_bytes, generators, clean_root, error) == 0L;
    // one bit, the lowest of the first generator
    generator_bytes[0] ^= 1u;
    const int sealed = clean_sealed && (qasm_lens_seal(generator_bytes, generators, flipped_root, error) == 0L);
    free(table);
    free(generator_bytes);
    if (!sealed)
    {
        return QASM_ERROR;
    }
    memcpy(clean, clean_root, ENGINE_SIGNUM_BYTES);
    memcpy(flipped, flipped_root, ENGINE_SIGNUM_BYTES);
    return 0L;
}
