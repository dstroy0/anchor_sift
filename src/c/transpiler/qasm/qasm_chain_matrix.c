// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// qasm_chain_matrix.c: matrices and one-qubit application
#include "qasm_chain_internal.h"

unsigned char *qasm_matrix_at(const QasmMatrix *matrix, unsigned int row, unsigned int column)
{
    // the row is widened to size_t so the index cannot wrap an unsigned int
    const size_t index = ((size_t)row * matrix->columns) + column;
    return &matrix->elements[index * matrix->field->element_bytes];
}

const void *qasm_element_at(const QasmField *field, const void *elements, size_t index)
{
    return &((const unsigned char *)elements)[index * field->element_bytes];
}

void qasm_matrix_release(QasmMatrix *matrix)
{
    if (matrix->elements != NULL)
    {
        // the rows widen to size_t exactly. The product cannot wrap an unsigned int
        const size_t count = (size_t)matrix->rows * matrix->columns;
        for (size_t index = 0u; index < count; index += 1u)
        {
            matrix->field->release(&matrix->elements[index * matrix->field->element_bytes]);
        }
        free(matrix->elements);
        matrix->elements = NULL;
    }
}

// rows x columns zeros; on an error the matrix is still one qasm_matrix_release takes
long qasm_matrix_alloc(const QasmField *field, unsigned int rows, unsigned int columns, QasmMatrix *matrix,
                       EngineError *error)
{
    // the rows widen to size_t exactly. The product cannot wrap an unsigned int
    const size_t count = (size_t)rows * columns;
    matrix->field = field;
    matrix->rows = rows;
    matrix->columns = columns;
    // an empty matrix still holds one zero-byte slot. Its storage is never a zero-byte allocation
    matrix->elements = (unsigned char *)calloc((count > 0u) ? count : 1u, field->element_bytes);
    if (QASM_CHECK(matrix->elements != NULL, matrix, error, ENGINE_ERROR_RESOURCE) == 0)
    {
        return QASM_ERROR;
    }
    long status = 0L;
    for (size_t index = 0u; (status == 0L) && (index < count); index += 1u)
    {
        status = field->copy(field->zero, &matrix->elements[index * field->element_bytes], error);
    }
    return status;
}

long qasm_matrix_copy(const QasmMatrix *from, QasmMatrix *to, EngineError *error)
{
    long status = qasm_matrix_alloc(from->field, from->rows, from->columns, to, error);
    for (unsigned int row = 0u; (status == 0L) && (row < from->rows); row += 1u)
    {
        for (unsigned int column = 0u; (status == 0L) && (column < from->columns); column += 1u)
        {
            status = from->field->copy(qasm_matrix_at(from, row, column), qasm_matrix_at(to, row, column), error);
        }
    }
    return status;
}

// product = left right, skipping a zero entry of `left` as mat_mul does
long qasm_matrix_multiply(const QasmMatrix *left, const QasmMatrix *right, QasmMatrix *product, EngineError *error)
{
    const QasmField *const field = left->field;
    long status = qasm_matrix_alloc(field, left->rows, right->columns, product, error);
    QasmSlot term;
    memset(&term, 0, sizeof(term));
    for (unsigned int row = 0u; (status == 0L) && (row < left->rows); row += 1u)
    {
        for (unsigned int inner = 0u; (status == 0L) && (inner < left->columns); inner += 1u)
        {
            const unsigned char *const entry = qasm_matrix_at(left, row, inner);
            const unsigned int columns = field->is_zero(entry) ? 0u : right->columns;
            for (unsigned int column = 0u; (status == 0L) && (column < columns); column += 1u)
            {
                unsigned char *const out = qasm_matrix_at(product, row, column);
                status = field->multiply(entry, qasm_matrix_at(right, inner, column), &term, error);
                status = (status == 0L) ? field->add(out, &term, out, error) : status;
            }
        }
    }
    field->release(&term);
    return status;
}

// accumulated += scalar matrix, entry by entry; a zero scalar adds nothing
static long qasm_matrix_scaled_add(QasmMatrix *accumulated, const void *scalar, const QasmMatrix *matrix,
                                   EngineError *error)
{
    const QasmField *const field = matrix->field;
    if (field->is_zero(scalar))
    {
        return 0L;
    }
    QasmSlot term;
    memset(&term, 0, sizeof(term));
    long status = 0L;
    for (unsigned int row = 0u; (status == 0L) && (row < matrix->rows); row += 1u)
    {
        for (unsigned int column = 0u; (status == 0L) && (column < matrix->columns); column += 1u)
        {
            unsigned char *const out = qasm_matrix_at(accumulated, row, column);
            status = field->multiply(scalar, qasm_matrix_at(matrix, row, column), &term, error);
            status = (status == 0L) ? field->add(out, &term, out, error) : status;
        }
    }
    field->release(&term);
    return status;
}

long qasm_matrix_conjugate_transpose(const QasmMatrix *matrix, QasmMatrix *dagger, EngineError *error)
{
    const QasmField *const field = matrix->field;
    long status = qasm_matrix_alloc(field, matrix->columns, matrix->rows, dagger, error);
    for (unsigned int row = 0u; (status == 0L) && (row < matrix->rows); row += 1u)
    {
        for (unsigned int column = 0u; (status == 0L) && (column < matrix->columns); column += 1u)
        {
            status = field->conjugate(qasm_matrix_at(matrix, row, column), qasm_matrix_at(dagger, column, row), error);
        }
    }
    return status;
}

static void qasm_matrix_swap_rows(QasmMatrix *matrix, unsigned int first, unsigned int second, unsigned char *swap_row)
{
    // the columns widen to size_t exactly
    const size_t row_bytes = (size_t)matrix->columns * matrix->field->element_bytes;
    // moving a slot's bytes moves the element whole, whatever it owns
    memcpy(swap_row, qasm_matrix_at(matrix, first, 0u), row_bytes);
    memcpy(qasm_matrix_at(matrix, first, 0u), qasm_matrix_at(matrix, second, 0u), row_bytes);
    memcpy(qasm_matrix_at(matrix, second, 0u), swap_row, row_bytes);
}

// Row `pivot` scaled to a leading one at `column`, and that column cleared from every other row.
static long qasm_matrix_eliminate(QasmMatrix *rows, unsigned int pivot, unsigned int column, EngineError *error)
{
    const QasmField *const field = rows->field;
    QasmSlot inverse;
    QasmSlot factor;
    QasmSlot term;
    memset(&inverse, 0, sizeof(inverse));
    memset(&factor, 0, sizeof(factor));
    memset(&term, 0, sizeof(term));
    long status = field->invert(qasm_matrix_at(rows, pivot, column), &inverse, error);
    for (unsigned int entry = 0u; (status == 0L) && (entry < rows->columns); entry += 1u)
    {
        unsigned char *const at = qasm_matrix_at(rows, pivot, entry);
        status = field->multiply(at, &inverse, at, error);
    }
    for (unsigned int other = 0u; (status == 0L) && (other < rows->rows); other += 1u)
    {
        const int clear = (other != pivot) && !field->is_zero(qasm_matrix_at(rows, other, column));
        status = clear ? field->copy(qasm_matrix_at(rows, other, column), &factor, error) : 0L;
        for (unsigned int entry = 0u; clear && (status == 0L) && (entry < rows->columns); entry += 1u)
        {
            unsigned char *const at = qasm_matrix_at(rows, other, entry);
            status = field->multiply(&factor, qasm_matrix_at(rows, pivot, entry), &term, error);
            status = (status == 0L) ? field->subtract(at, &term, at, error) : status;
        }
    }
    field->release(&inverse);
    field->release(&factor);
    field->release(&term);
    return status;
}

// The exact rank factorization M = C F: C the pivot columns of M, F the nonzero rows of M's reduced echelon form, the
// inner dimension the rank. Gaussian elimination over the field, rank_factorization's pivot order.
long qasm_matrix_factor(const QasmMatrix *matrix, QasmMatrix *pivot_columns, QasmMatrix *reduced_rows,
                        EngineError *error)
{
    const QasmField *const field = matrix->field;
    const unsigned int height = matrix->rows;
    const unsigned int width = matrix->columns;
    QasmMatrix rows = QASM_MATRIX_EMPTY;
    unsigned int *const pivots = (unsigned int *)malloc(((width > 0u) ? width : 1u) * sizeof(unsigned int));
    unsigned char *const swap_row = (unsigned char *)malloc(((width > 0u) ? width : 1u) * field->element_bytes);
    long status = (QASM_CHECK((pivots != NULL) && (swap_row != NULL), matrix, error, ENGINE_ERROR_RESOURCE) != 0)
                      ? qasm_matrix_copy(matrix, &rows, error)
                      : QASM_ERROR;
    unsigned int rank = 0u;
    for (unsigned int column = 0u; (status == 0L) && (rank < height) && (column < width); column += 1u)
    {
        unsigned int chosen = rank;
        while ((chosen < height) && field->is_zero(qasm_matrix_at(&rows, chosen, column)))
        {
            chosen += 1u;
        }
        if (chosen < height)
        {
            if (chosen != rank)
            {
                qasm_matrix_swap_rows(&rows, rank, chosen, swap_row);
            }
            status = qasm_matrix_eliminate(&rows, rank, column, error);
            pivots[rank] = column;
            rank += 1u;
        }
    }
    status = (status == 0L) ? qasm_matrix_alloc(field, height, rank, pivot_columns, error) : status;
    for (unsigned int row = 0u; (status == 0L) && (row < height); row += 1u)
    {
        for (unsigned int inner = 0u; (status == 0L) && (inner < rank); inner += 1u)
        {
            status = field->copy(qasm_matrix_at(matrix, row, pivots[inner]), qasm_matrix_at(pivot_columns, row, inner),
                                 error);
        }
    }
    status = (status == 0L) ? qasm_matrix_alloc(field, rank, width, reduced_rows, error) : status;
    for (unsigned int row = 0u; (status == 0L) && (row < rank); row += 1u)
    {
        for (unsigned int column = 0u; (status == 0L) && (column < width); column += 1u)
        {
            status = field->copy(qasm_matrix_at(&rows, row, column), qasm_matrix_at(reduced_rows, row, column), error);
        }
    }
    qasm_matrix_release(&rows);
    free(pivots);
    free(swap_row);
    return status;
}

void qasm_chain_release(QasmChain *chain)
{
    if ((chain != NULL) && (chain->tensors != NULL))
    {
        for (unsigned int tensor = 0u; tensor < (2u * chain->sites); tensor += 1u)
        {
            qasm_matrix_release(&chain->tensors[tensor]);
        }
        free(chain->tensors);
        chain->tensors = NULL;
        chain->sites = 0u;
    }
}

long qasm_chain_alloc(QasmChain *chain, const QasmField *field, unsigned int sites, EngineError *error)
{
    if (error == NULL)
    {
        return QASM_ERROR;
    }
    const int ok = (chain != NULL) && (field != NULL) && (field->element_bytes <= sizeof(QasmSlot)) && (sites >= 1u) &&
                   (sites <= (UINT_MAX / 2u));
    if (QASM_CHECK(ok, chain, error, ENGINE_ERROR_REQUEST) == 0)
    {
        return QASM_ERROR;
    }
    // the sites widen to size_t exactly
    QasmMatrix *const tensors = (QasmMatrix *)calloc(2u * (size_t)sites, sizeof(QasmMatrix));
    if (QASM_CHECK(tensors != NULL, chain, error, ENGINE_ERROR_RESOURCE) == 0)
    {
        return QASM_ERROR;
    }
    chain->field = field;
    chain->sites = sites;
    chain->tensors = tensors;
    long status = 0L;
    for (unsigned int site = 0u; (status == 0L) && (site < sites); site += 1u)
    {
        status = qasm_matrix_alloc(field, 1u, 1u, &tensors[2u * site], error);
        status = (status == 0L) ? field->copy(field->one, qasm_matrix_at(&tensors[2u * site], 0u, 0u), error) : status;
        status = (status == 0L) ? qasm_matrix_alloc(field, 1u, 1u, &tensors[(2u * site) + 1u], error) : status;
    }
    if (status != 0L)
    {
        qasm_chain_release(chain);
    }
    return status;
}

long qasm_chain_apply_one(QasmChain *chain, const void *gate, unsigned int site, EngineError *error)
{
    if (error == NULL)
    {
        return QASM_ERROR;
    }
    if (QASM_CHECK((chain != NULL) && (chain->tensors != NULL) && (gate != NULL) && (site < chain->sites), chain, error,
                   ENGINE_ERROR_REQUEST) == 0)
    {
        return QASM_ERROR;
    }
    const QasmField *const field = chain->field;
    QasmMatrix *const sigma = &chain->tensors[2u * site];
    QasmMatrix fresh[2] = {QASM_MATRIX_EMPTY, QASM_MATRIX_EMPTY};
    long status = 0L;
    for (unsigned int out = 0u; (status == 0L) && (out < 2u); out += 1u)
    {
        status = qasm_matrix_alloc(field, sigma[0].rows, sigma[0].columns, &fresh[out], error);
        for (unsigned int in = 0u; (status == 0L) && (in < 2u); in += 1u)
        {
            status =
                qasm_matrix_scaled_add(&fresh[out], qasm_element_at(field, gate, (2u * out) + in), &sigma[in], error);
        }
    }
    for (unsigned int out = 0u; out < 2u; out += 1u)
    {
        if (status == 0L)
        {
            qasm_matrix_release(&sigma[out]);
            sigma[out] = fresh[out];
        }
        else
        {
            qasm_matrix_release(&fresh[out]);
        }
    }
    return status;
}
