// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// qasm_chain_apply.c: two-qubit application, amplitudes, expectation and the seal
#include "qasm_chain_internal.h"

long qasm_chain_apply_two(QasmChain *chain, const void *gate, unsigned int site, EngineError *error)
{
    if (error == NULL)
    {
        return QASM_ERROR;
    }
    if (QASM_CHECK((chain != NULL) && (chain->tensors != NULL) && (gate != NULL) && (site < chain->sites) &&
                       ((site + 1u) < chain->sites),
                   chain, error, ENGINE_ERROR_REQUEST) == 0)
    {
        return QASM_ERROR;
    }
    const QasmField *const field = chain->field;
    QasmMatrix *const left_site = &chain->tensors[2u * site];
    QasmMatrix *const right_site = &chain->tensors[2u * (site + 1u)];
    const unsigned int left_bond = left_site[0].rows;
    const unsigned int right_bond = right_site[0].columns;
    // theta[2 s0 + s1] = A_s0 B_s1, each (left bond) x (right bond)
    QasmMatrix theta[4] = {QASM_MATRIX_EMPTY, QASM_MATRIX_EMPTY, QASM_MATRIX_EMPTY, QASM_MATRIX_EMPTY};
    QasmMatrix joined = QASM_MATRIX_EMPTY;
    QasmMatrix pivot_columns = QASM_MATRIX_EMPTY;
    QasmMatrix reduced_rows = QASM_MATRIX_EMPTY;
    QasmMatrix fresh[4] = {QASM_MATRIX_EMPTY, QASM_MATRIX_EMPTY, QASM_MATRIX_EMPTY, QASM_MATRIX_EMPTY};
    QasmSlot term;
    memset(&term, 0, sizeof(term));
    long status = 0L;
    for (unsigned int pair = 0u; (status == 0L) && (pair < 4u); pair += 1u)
    {
        status = qasm_matrix_multiply(&left_site[pair / 2u], &right_site[pair % 2u], &theta[pair], error);
    }
    // joined[2 x + t0][t1 (right bond) + y] = sum over (s0, s1) of gate[2 t0 + t1][2 s0 + s1] theta[2 s0 + s1][x][y]
    status = (status == 0L) ? qasm_matrix_alloc(field, 2u * left_bond, 2u * right_bond, &joined, error) : status;
    for (unsigned int out = 0u; (status == 0L) && (out < 4u); out += 1u)
    {
        for (unsigned int in = 0u; (status == 0L) && (in < 4u); in += 1u)
        {
            const void *const coefficient = qasm_element_at(field, gate, (4u * out) + in);
            const unsigned int rows = field->is_zero(coefficient) ? 0u : left_bond;
            for (unsigned int row = 0u; (status == 0L) && (row < rows); row += 1u)
            {
                for (unsigned int column = 0u; (status == 0L) && (column < right_bond); column += 1u)
                {
                    unsigned char *const target =
                        qasm_matrix_at(&joined, (2u * row) + (out / 2u), ((out % 2u) * right_bond) + column);
                    status = field->multiply(coefficient, qasm_matrix_at(&theta[in], row, column), &term, error);
                    status = (status == 0L) ? field->add(target, &term, target, error) : status;
                }
            }
        }
    }
    status = (status == 0L) ? qasm_matrix_factor(&joined, &pivot_columns, &reduced_rows, error) : status;
    const unsigned int rank = pivot_columns.columns;
    for (unsigned int sigma = 0u; (status == 0L) && (sigma < 2u); sigma += 1u)
    {
        status = qasm_matrix_alloc(field, left_bond, rank, &fresh[sigma], error);
        status = (status == 0L) ? qasm_matrix_alloc(field, rank, right_bond, &fresh[2u + sigma], error) : status;
        for (unsigned int row = 0u; (status == 0L) && (row < left_bond); row += 1u)
        {
            for (unsigned int inner = 0u; (status == 0L) && (inner < rank); inner += 1u)
            {
                status = field->copy(qasm_matrix_at(&pivot_columns, (2u * row) + sigma, inner),
                                     qasm_matrix_at(&fresh[sigma], row, inner), error);
            }
        }
        for (unsigned int inner = 0u; (status == 0L) && (inner < rank); inner += 1u)
        {
            for (unsigned int column = 0u; (status == 0L) && (column < right_bond); column += 1u)
            {
                status = field->copy(qasm_matrix_at(&reduced_rows, inner, (sigma * right_bond) + column),
                                     qasm_matrix_at(&fresh[2u + sigma], inner, column), error);
            }
        }
    }
    for (unsigned int sigma = 0u; sigma < 2u; sigma += 1u)
    {
        if (status == 0L)
        {
            qasm_matrix_release(&left_site[sigma]);
            qasm_matrix_release(&right_site[sigma]);
            left_site[sigma] = fresh[sigma];
            right_site[sigma] = fresh[2u + sigma];
        }
        else
        {
            qasm_matrix_release(&fresh[sigma]);
            qasm_matrix_release(&fresh[2u + sigma]);
        }
    }
    for (unsigned int pair = 0u; pair < 4u; pair += 1u)
    {
        qasm_matrix_release(&theta[pair]);
    }
    qasm_matrix_release(&joined);
    qasm_matrix_release(&pivot_columns);
    qasm_matrix_release(&reduced_rows);
    field->release(&term);
    return status;
}

long qasm_chain_amplitude(const QasmChain *chain, const unsigned char *bits, void *amplitude, EngineError *error)
{
    if (error == NULL)
    {
        return QASM_ERROR;
    }
    int ok = (chain != NULL) && (chain->tensors != NULL) && (bits != NULL) && (amplitude != NULL);
    for (unsigned int site = 0u; (ok != 0) && (site < chain->sites); site += 1u)
    {
        ok = (bits[site] <= 1u);
    }
    if (QASM_CHECK(ok, chain, error, ENGINE_ERROR_REQUEST) == 0)
    {
        return QASM_ERROR;
    }
    QasmMatrix product = QASM_MATRIX_EMPTY;
    long status = qasm_matrix_copy(&chain->tensors[bits[0]], &product, error);
    for (unsigned int site = 1u; (status == 0L) && (site < chain->sites); site += 1u)
    {
        QasmMatrix next = QASM_MATRIX_EMPTY;
        status = qasm_matrix_multiply(&product, &chain->tensors[(2u * site) + bits[site]], &next, error);
        qasm_matrix_release(&product);
        product = next;
    }
    status = (status == 0L) ? chain->field->copy(qasm_matrix_at(&product, 0u, 0u), amplitude, error) : status;
    qasm_matrix_release(&product);
    return status;
}

// the term (A_sp^dagger L) A_s, scaled by the operator's coefficient
static long qasm_chain_lens_term(const QasmMatrix *sigma_out, const QasmMatrix *left, const QasmMatrix *sigma_in,
                                 const void *coefficient, QasmMatrix *term, EngineError *error)
{
    const QasmField *const field = left->field;
    QasmMatrix dagger = QASM_MATRIX_EMPTY;
    QasmMatrix half = QASM_MATRIX_EMPTY;
    long status = qasm_matrix_conjugate_transpose(sigma_out, &dagger, error);
    status = (status == 0L) ? qasm_matrix_multiply(&dagger, left, &half, error) : status;
    status = (status == 0L) ? qasm_matrix_multiply(&half, sigma_in, term, error) : status;
    for (unsigned int row = 0u; (status == 0L) && (row < term->rows); row += 1u)
    {
        for (unsigned int column = 0u; (status == 0L) && (column < term->columns); column += 1u)
        {
            unsigned char *const at = qasm_matrix_at(term, row, column);
            status = field->multiply(coefficient, at, at, error);
        }
    }
    qasm_matrix_release(&dagger);
    qasm_matrix_release(&half);
    return status;
}

long qasm_chain_expectation(const QasmChain *chain, const void *operators, void *value, EngineError *error)
{
    if (error == NULL)
    {
        return QASM_ERROR;
    }
    if (QASM_CHECK((chain != NULL) && (chain->tensors != NULL) && (operators != NULL) && (value != NULL), chain, error,
                   ENGINE_ERROR_REQUEST) == 0)
    {
        return QASM_ERROR;
    }
    const QasmField *const field = chain->field;
    QasmMatrix left = QASM_MATRIX_EMPTY;
    long status = qasm_matrix_alloc(field, 1u, 1u, &left, error);
    status = (status == 0L) ? field->copy(field->one, qasm_matrix_at(&left, 0u, 0u), error) : status;
    for (unsigned int site = 0u; (status == 0L) && (site < chain->sites); site += 1u)
    {
        const QasmMatrix *const sigma = &chain->tensors[2u * site];
        QasmMatrix accumulated = QASM_MATRIX_EMPTY;
        int started = 0;
        for (unsigned int pair = 0u; (status == 0L) && (pair < 4u); pair += 1u)
        {
            // the site widens to size_t exactly. Four entries a site cannot wrap an unsigned int
            const void *const coefficient = qasm_element_at(field, operators, (4u * (size_t)site) + pair);
            if (!field->is_zero(coefficient))
            {
                QasmMatrix term = QASM_MATRIX_EMPTY;
                status = qasm_chain_lens_term(&sigma[pair / 2u], &left, &sigma[pair % 2u], coefficient, &term, error);
                for (unsigned int row = 0u; started && (status == 0L) && (row < term.rows); row += 1u)
                {
                    for (unsigned int column = 0u; (status == 0L) && (column < term.columns); column += 1u)
                    {
                        unsigned char *const at = qasm_matrix_at(&accumulated, row, column);
                        status = field->add(at, qasm_matrix_at(&term, row, column), at, error);
                    }
                }
                if (started == 0)
                {
                    accumulated = term;
                    started = 1;
                }
                else
                {
                    qasm_matrix_release(&term);
                }
            }
        }
        if ((status == 0L) && (started == 0))
        {
            status = qasm_matrix_alloc(field, sigma[0].columns, sigma[0].columns, &accumulated, error);
        }
        qasm_matrix_release(&left);
        left = accumulated;
    }
    status = (status == 0L) ? field->copy(qasm_matrix_at(&left, 0u, 0u), value, error) : status;
    qasm_matrix_release(&left);
    return status;
}

long qasm_chain_norm(const QasmChain *chain, void *norm, EngineError *error)
{
    if (error == NULL)
    {
        return QASM_ERROR;
    }
    if (QASM_CHECK((chain != NULL) && (chain->tensors != NULL) && (norm != NULL), chain, error, ENGINE_ERROR_REQUEST) ==
        0)
    {
        return QASM_ERROR;
    }
    const QasmField *const field = chain->field;
    // the sites widen to size_t exactly. Four entries a site cannot wrap an unsigned int
    const size_t count = 4u * (size_t)chain->sites;
    unsigned char *const identities = (unsigned char *)calloc(count, field->element_bytes);
    if (QASM_CHECK(identities != NULL, chain, error, ENGINE_ERROR_RESOURCE) == 0)
    {
        return QASM_ERROR;
    }
    long status = 0L;
    for (size_t index = 0u; (status == 0L) && (index < count); index += 1u)
    {
        // the diagonal of each site's 2 x 2 is its entries 0 and 3
        const int diagonal = ((index % 4u) == 0u) || ((index % 4u) == 3u);
        status = field->copy(diagonal ? field->one : field->zero, &identities[index * field->element_bytes], error);
    }
    status = (status == 0L) ? qasm_chain_expectation(chain, identities, norm, error) : status;
    for (size_t index = 0u; index < count; index += 1u)
    {
        field->release(&identities[index * field->element_bytes]);
    }
    free(identities);
    return status;
}

unsigned int qasm_chain_bond(const QasmChain *chain, unsigned int site)
{
    // site is tested below the sites first. Site + 1 cannot wrap
    const int inside =
        (chain != NULL) && (chain->tensors != NULL) && (site < chain->sites) && ((site + 1u) < chain->sites);
    return inside ? chain->tensors[2u * site].columns : 0u;
}

unsigned long long qasm_chain_elements(const QasmChain *chain)
{
    unsigned long long count = 0ull;
    for (unsigned int site = 0u; (chain != NULL) && (chain->tensors != NULL) && (site < chain->sites); site += 1u)
    {
        const QasmMatrix *const sigma = &chain->tensors[2u * site];
        // both bonds widen to unsigned long long exactly before they multiply
        count += 2ull * (unsigned long long)sigma->rows * (unsigned long long)sigma->columns;
    }
    return count;
}

long qasm_chain_seal(const QasmChain *chain, unsigned char *signum, EngineError *error)
{
    if (error == NULL)
    {
        return QASM_ERROR;
    }
    if (QASM_CHECK((chain != NULL) && (chain->tensors != NULL) && (chain->field == &qasm_number_field) &&
                       (signum != NULL),
                   chain, error, ENGINE_ERROR_REQUEST) == 0)
    {
        return QASM_ERROR;
    }
    size_t total = 0u;
    for (unsigned int tensor = 0u; tensor < (2u * chain->sites); tensor += 1u)
    {
        const QasmMatrix *const matrix = &chain->tensors[tensor];
        // the rows widen to size_t exactly. The product cannot wrap an unsigned int
        const size_t count = (size_t)matrix->rows * matrix->columns;
        for (size_t index = 0u; index < count; index += 1u)
        {
            total += qasm_number_bytes(&((const QasmNumber *)(const void *)matrix->elements)[index], NULL);
        }
    }
    // a chain whose every bond fell to rank 0 holds no entries and seals an empty stream, as the Python digests one
    unsigned char *const bytes = (unsigned char *)malloc((total > 0u) ? total : 1u);
    if (QASM_CHECK(bytes != NULL, chain, error, ENGINE_ERROR_RESOURCE) == 0)
    {
        return QASM_ERROR;
    }
    size_t at = 0u;
    for (unsigned int tensor = 0u; tensor < (2u * chain->sites); tensor += 1u)
    {
        const QasmMatrix *const matrix = &chain->tensors[tensor];
        // the rows widen to size_t exactly. The product cannot wrap an unsigned int
        const size_t count = (size_t)matrix->rows * matrix->columns;
        for (size_t index = 0u; index < count; index += 1u)
        {
            at += qasm_number_bytes(&((const QasmNumber *)(const void *)matrix->elements)[index], &bytes[at]);
        }
    }
    const ObsignatioSealRequest request = {bytes, total, signum, error};
    const long sealed = obsignatio_seal(&request);
    free(bytes);
    return (sealed == 0L) ? 0L : QASM_ERROR;
}
