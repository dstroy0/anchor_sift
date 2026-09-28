// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// period_select.cu: the lattice, the null axis, selection, reading and printing
#include "period_internal.h"

static int period_lattice_fill(const PeriodRequest *request, PeriodLattice *lattice, unsigned long long *voxels)
{
    EngineError *const error = request->error;
    const unsigned int rank = request->rank;
    if (!PERIOD_CHECK((rank >= 1u) && (rank <= ENGINE_ARRAY_RANK), &request->rank, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    unsigned long long count = 1ull;
    for (unsigned int axis = 0u; axis < rank; axis += 1u)
    {
        const unsigned long long extent = request->extent[axis];
        if (!PERIOD_CHECK((extent >= 1ull) && (extent <= (PERIOD_VOXELS_MAX / count)), &request->extent[axis], error,
                          ENGINE_ERROR_REQUEST))
        {
            return 0;
        }
        count *= extent;
    }
    memset(lattice, 0, sizeof(*lattice));
    lattice->rank = rank;
    unsigned long long stride = 1ull;
    for (unsigned int axis = rank; axis > 0u; axis -= 1u)
    {
        const unsigned long long extent = request->extent[axis - 1u];
        const unsigned long long lags = extent / 2ull;
        // every count here is at most the voxel count, which was held below 2^32. Each narrows exactly
        lattice->extent[axis - 1u] = (unsigned int)extent;
        lattice->stride[axis - 1u] = (unsigned int)stride;
        lattice->usable[axis - 1u] = (unsigned int)(extent - lags);
        lattice->pairs[axis - 1u] = (unsigned int)((extent - lags) * (count / extent));
        stride *= extent;
    }
    unsigned long long first = 0ull;
    for (unsigned int axis = 0u; axis < rank; axis += 1u)
    {
        lattice->first[axis] = first;
        first += request->extent[axis] / 2ull;
    }
    lattice->lag_total = first;
    lattice->voxels = count;
    *voxels = count;
    return 1;
}

static unsigned int period_grid_columns(const PeriodLattice *lattice, EngineError *error)
{
    int device = 0;
    int processors = 0;
    int threads_each = 0;
    const int read =
        PERIOD_STATUS_CHECK(cudaGetDevice(&device), &device, error) &&
        PERIOD_STATUS_CHECK(cudaDeviceGetAttribute(&processors, cudaDevAttrMultiProcessorCount, device), &processors,
                            error) &&
        PERIOD_STATUS_CHECK(cudaDeviceGetAttribute(&threads_each, cudaDevAttrMaxThreadsPerMultiProcessor, device),
                            &threads_each, error);
    if (read == 0)
    {
        return 0u;
    }
    // both attributes are positive counts the runtime reports. They re-sign to unsigned exactly
    const unsigned long long resident =
        (unsigned long long)processors * ((unsigned long long)threads_each / PERIOD_THREADS);
    unsigned long long widest = 0ull;
    for (unsigned int axis = 0u; axis < lattice->rank; axis += 1u)
    {
        widest = (lattice->pairs[axis] > widest) ? lattice->pairs[axis] : widest;
    }
    const unsigned long long needed = (widest + PERIOD_THREADS - 1ull) / PERIOD_THREADS;
    const unsigned long long columns = (needed < resident) ? needed : resident;
    // columns is at most the resident block count, far below 2^32
    return (unsigned int)((columns != 0ull) ? columns : 1ull);
}

static int period_count(const PeriodPass *pass, const PeriodLattice *lattice, int with_agreement, EngineError *error)
{
    int ok =
        PERIOD_STATUS_CHECK(cudaMemset(pass->device_histogram, 0, PERIOD_VALUES * sizeof(unsigned int)),
                            pass->device_histogram, error) &&
        PERIOD_STATUS_CHECK(cudaMemset(pass->device_agreement, 0, pass->agreement_entries * sizeof(unsigned long long)),
                            pass->device_agreement, error);
    if (ok != 0)
    {
        const unsigned long long needed = (pass->voxels + PERIOD_THREADS - 1ull) / PERIOD_THREADS;
        // the block count is held below the resident count, far below 2^32
        const unsigned int blocks =
            (unsigned int)((needed < (unsigned long long)pass->columns) ? needed : pass->columns);
        period_histogram_kernel<<<blocks, PERIOD_THREADS>>>(pass->lanes, pass->voxels, pass->device_histogram);
        ok = PERIOD_STATUS_CHECK(cudaGetLastError(), pass->device_histogram, error);
    }
    if ((ok != 0) && (with_agreement != 0) && (lattice->lag_total != 0ull))
    {
        // the row count is held at or below the grid's row limit
        const unsigned int rows =
            (unsigned int)((lattice->lag_total < PERIOD_GRID_ROWS_MAX) ? lattice->lag_total : PERIOD_GRID_ROWS_MAX);
        const dim3 grid(pass->columns, rows, 1u);
        period_agreement_kernel<<<grid, PERIOD_THREADS>>>(pass->lanes, *lattice, pass->device_agreement);
        ok = PERIOD_STATUS_CHECK(cudaGetLastError(), pass->device_agreement, error);
    }
    return ok &&
           PERIOD_STATUS_CHECK(cudaMemcpy(pass->histogram, pass->device_histogram, PERIOD_VALUES * sizeof(unsigned int),
                                          cudaMemcpyDeviceToHost),
                               pass->histogram, error) &&
           PERIOD_STATUS_CHECK(cudaMemcpy(pass->agreement, pass->device_agreement,
                                          pass->agreement_entries * sizeof(unsigned long long), cudaMemcpyDeviceToHost),
                               pass->agreement, error);
}

static int period_request_valid(const PeriodRequest *request, unsigned long long entries)
{
    EngineError *const error = request->error;
    const unsigned long long band_needed = request->draws * request->rank;
    const int drawn = (request->null_top == NULL)
                          ? ((request->draws >= 1ull) && (request->draws <= (PERIOD_VOXELS_MAX / ENGINE_ARRAY_RANK)))
                          : (request->draws == 0ull);
    return PERIOD_CHECK(drawn, &request->draws, error, ENGINE_ERROR_REQUEST) &&
           PERIOD_CHECK((request->agreement == NULL) || (request->agreement_capacity >= entries),
                        &request->agreement_capacity, error, ENGINE_ERROR_REQUEST) &&
           PERIOD_CHECK((request->band == NULL) || (request->band_capacity >= band_needed), &request->band_capacity,
                        error, ENGINE_ERROR_REQUEST);
}

static void period_axis_open(const PeriodLattice *lattice, unsigned int axis, PeriodAxis *result)
{
    memset(result, 0, sizeof(*result));
    result->extent = lattice->extent[axis];
    result->lags = lattice->extent[axis] / 2u;
    result->pairs_per_lag = lattice->pairs[axis];
}

// The one axis's null: shuffle each line along the axis, count agreement, and read the strongest peak
// the shuffle reaches. That best height is one draw of the band.
static int period_null_axis(const PeriodRequest *request, const PeriodLattice *lattice, unsigned long long counter,
                            unsigned int axis, unsigned short *device_shuffled, const PeriodPass *shuffled_pass,
                            const unsigned int *histogram, PeriodMargin *height, EngineError *error)
{
    PeriodShuffle shuffle;
    period_shuffle_fill(&shuffle, &request->content, counter);
    if (!PERIOD_STATUS_CHECK(cudaMemcpy(device_shuffled, request->device_lanes,
                                        (size_t)lattice->voxels * sizeof(unsigned short), cudaMemcpyDeviceToDevice),
                             device_shuffled, error))
    {
        return 0;
    }
    const unsigned long long lines = lattice->voxels / lattice->extent[axis];
    const unsigned long long needed = (lines + PERIOD_THREADS - 1ull) / PERIOD_THREADS;
    // the block count is held below the resident count, far below 2^32
    const unsigned int blocks =
        (unsigned int)((needed < (unsigned long long)shuffled_pass->columns) ? needed : shuffled_pass->columns);
    period_line_shuffle_kernel<<<blocks, PERIOD_THREADS>>>(device_shuffled, shuffle, *lattice, axis, lines);
    int ok = PERIOD_STATUS_CHECK(cudaGetLastError(), device_shuffled, error) &&
             period_count(shuffled_pass, lattice, 1, error) &&
             PERIOD_CHECK(memcmp(histogram, shuffled_pass->histogram, PERIOD_VALUES * sizeof(unsigned int)) == 0,
                          shuffled_pass->histogram, error, ENGINE_ERROR_LOGIC);
    if (ok != 0)
    {
        PeriodAxis drawn;
        period_axis_open(lattice, axis, &drawn);
        period_strongest(&shuffled_pass->agreement[lattice->first[axis]], &drawn);
        height->numerator = (drawn.candidate != 0ull) ? drawn.margin.numerator : 0ull;
        height->denominator = drawn.pairs_per_lag;
    }
    return ok;
}

// The period is the smallest candidate whose height clears the band top. An empty band, or a given
// top of zero, lets any peak through. The smallest peak wins; when nothing clears, the period is
// zero and the display candidate is the strongest peak.
static void period_select(const unsigned long long *same, const PeriodLattice *lattice, unsigned int axis,
                          PeriodMargin *band, unsigned long long count, const PeriodMargin *given_top,
                          PeriodAxis *result)
{
    period_axis_open(lattice, axis, result);
    qsort(band, (size_t)count, sizeof(PeriodMargin), period_margin_compare);
    result->band_count = count;
    PeriodMargin top = {0ull, result->pairs_per_lag};
    if (count != 0ull)
    {
        result->band_bottom = band[0];
        result->band_top = band[count - 1ull];
        top = band[count - 1ull];
    }
    if (given_top != NULL)
    {
        result->band_bottom = *given_top;
        result->band_top = *given_top;
        top = *given_top;
    }
    if (period_fundamental(same, &top, result) != 0)
    {
        result->period = result->candidate;
    }
    else
    {
        period_strongest(same, result);
        result->period = 0ull;
    }
}

extern "C" long period_read(const PeriodRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return PERIOD_ERROR;
    }
    EngineError *const error = request->error;
    if (!PERIOD_CHECK((request->device_lanes != NULL) && (request->measurement != NULL), request, error,
                      ENGINE_ERROR_REQUEST))
    {
        return PERIOD_ERROR;
    }
    PeriodLattice lattice;
    unsigned long long voxels = 0ull;
    if (period_lattice_fill(request, &lattice, &voxels) == 0)
    {
        return PERIOD_ERROR;
    }
    const unsigned long long entries = lattice.lag_total;
    if (period_request_valid(request, entries) == 0)
    {
        return PERIOD_ERROR;
    }
    const unsigned int columns = period_grid_columns(&lattice, error);
    if (columns == 0u)
    {
        return PERIOD_ERROR;
    }
    const unsigned long long draws = request->draws;
    const size_t agreement_entries = (size_t)((entries != 0ull) ? entries : 1ull);
    unsigned int *const histogram = (unsigned int *)malloc(PERIOD_VALUES * sizeof(unsigned int));
    unsigned int *const shuffled_histogram = (unsigned int *)malloc(PERIOD_VALUES * sizeof(unsigned int));
    unsigned long long *const agreement = (unsigned long long *)calloc(agreement_entries, sizeof(unsigned long long));
    unsigned long long *const shuffled_agreement =
        (unsigned long long *)calloc(agreement_entries, sizeof(unsigned long long));
    const size_t band_slots = (size_t)((draws != 0ull) ? (draws * lattice.rank) : 1ull);
    PeriodMargin *const bands = (PeriodMargin *)calloc(band_slots, sizeof(PeriodMargin));
    unsigned long long band_counts[ENGINE_ARRAY_RANK] = {0ull};
    int ok = PERIOD_CHECK((histogram != NULL) && (shuffled_histogram != NULL) && (agreement != NULL) &&
                              (shuffled_agreement != NULL) && (bands != NULL),
                          request, error, ENGINE_ERROR_RESOURCE) &&
             period_reserve(voxels, agreement_entries, error);
    const PeriodResident *const resident = &g_period_resident;
    PeriodPass pass = {request->device_lanes, voxels,    columns,   resident->histogram,
                       resident->agreement,   histogram, agreement, agreement_entries};
    ok = ok && period_count(&pass, &lattice, 1, error);
    unsigned long long collisions = 0ull;
    if (ok != 0)
    {
        unsigned long long counted = 0ull;
        for (unsigned int value = 0u; value < PERIOD_VALUES; value += 1u)
        {
            counted += histogram[value];
            collisions += (unsigned long long)histogram[value] * histogram[value];
        }
        ok = PERIOD_CHECK(counted == voxels, histogram, error, ENGINE_ERROR_LOGIC);
    }
    PeriodMeasurement *const measurement = request->measurement;
    memset(measurement, 0, sizeof(*measurement));
    measurement->rank = lattice.rank;
    measurement->voxels = voxels;
    measurement->collisions = collisions;
    measurement->draws = draws;
    PeriodPass shuffled_pass = {
        resident->shuffled, voxels,           columns, resident->histogram, resident->agreement, shuffled_histogram,
        shuffled_agreement, agreement_entries};
    for (unsigned long long draw = 0ull; (ok != 0) && (voxels >= 2ull) && (draw < draws); draw += 1ull)
    {
        for (unsigned int axis = 0u; (ok != 0) && (axis < lattice.rank); axis += 1u)
        {
            PeriodMargin height;
            ok = period_null_axis(request, &lattice, (draw * lattice.rank) + axis, axis, resident->shuffled,
                                  &shuffled_pass, histogram, &height, error);
            if ((ok != 0) && (height.numerator != 0ull))
            {
                bands[(axis * draws) + band_counts[axis]] = height;
                band_counts[axis] += 1ull;
            }
        }
    }
    for (unsigned int axis = 0u; (ok != 0) && (axis < lattice.rank); axis += 1u)
    {
        period_select(&agreement[lattice.first[axis]], &lattice, axis, &bands[axis * draws], band_counts[axis],
                      (request->null_top != NULL) ? &request->null_top[axis] : NULL, &measurement->axis[axis]);
    }
    if ((ok != 0) && (request->agreement != NULL) && (entries != 0ull))
    {
        memcpy(request->agreement, agreement, (size_t)entries * sizeof(unsigned long long));
    }
    if ((ok != 0) && (request->band != NULL))
    {
        memcpy(request->band, bands, (size_t)(draws * lattice.rank) * sizeof(PeriodMargin));
    }
    free(histogram);
    free(shuffled_histogram);
    free(agreement);
    free(shuffled_agreement);
    free(bands);
    return (ok != 0) ? 0L : PERIOD_ERROR;
}

extern "C" long period_draw(const PeriodRequest *request, unsigned long long draw, PeriodMargin *heights)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return PERIOD_ERROR;
    }
    EngineError *const error = request->error;
    if (!PERIOD_CHECK((request->device_lanes != NULL) && (heights != NULL), request, error, ENGINE_ERROR_REQUEST))
    {
        return PERIOD_ERROR;
    }
    PeriodLattice lattice;
    unsigned long long voxels = 0ull;
    if (period_lattice_fill(request, &lattice, &voxels) == 0)
    {
        return PERIOD_ERROR;
    }
    const unsigned int columns = period_grid_columns(&lattice, error);
    if (columns == 0u)
    {
        return PERIOD_ERROR;
    }
    const unsigned long long entries = lattice.lag_total;
    const size_t agreement_entries = (size_t)((entries != 0ull) ? entries : 1ull);
    unsigned int *const histogram = (unsigned int *)malloc(PERIOD_VALUES * sizeof(unsigned int));
    unsigned int *const shuffled_histogram = (unsigned int *)malloc(PERIOD_VALUES * sizeof(unsigned int));
    unsigned long long *const shuffled_agreement =
        (unsigned long long *)calloc(agreement_entries, sizeof(unsigned long long));
    int ok = PERIOD_CHECK((histogram != NULL) && (shuffled_histogram != NULL) && (shuffled_agreement != NULL), request,
                          error, ENGINE_ERROR_RESOURCE) &&
             period_reserve(voxels, agreement_entries, error);
    const PeriodResident *const resident = &g_period_resident;
    PeriodPass pass = {
        request->device_lanes, voxels,           columns, resident->histogram, resident->agreement, histogram,
        shuffled_agreement,    agreement_entries};
    PeriodPass shuffled_pass = {
        resident->shuffled, voxels,           columns, resident->histogram, resident->agreement, shuffled_histogram,
        shuffled_agreement, agreement_entries};
    ok = ok && period_count(&pass, &lattice, 0, error);
    for (unsigned int axis = 0u; (ok != 0) && (axis < lattice.rank); axis += 1u)
    {
        PeriodAxis open;
        period_axis_open(&lattice, axis, &open);
        heights[axis].numerator = 0ull;
        heights[axis].denominator = open.pairs_per_lag;
        if (voxels >= 2ull)
        {
            ok = period_null_axis(request, &lattice, (draw * lattice.rank) + axis, axis, resident->shuffled,
                                  &shuffled_pass, histogram, &heights[axis], error);
        }
    }
    free(histogram);
    free(shuffled_histogram);
    free(shuffled_agreement);
    return (ok != 0) ? 0L : PERIOD_ERROR;
}

static void period_margin_text(ScripturaLine *line, const PeriodMargin *margin)
{
    scriptura_decimal(line, margin->numerator, 1u);
    scriptura_character(line, '/');
    scriptura_decimal(line, margin->denominator, 1u);
}

extern "C" int period_print(const PeriodMeasurement *measurement, FILE *file)
{
    if ((measurement == NULL) || (file == NULL))
    {
        return 0;
    }
    ScripturaLine line;
    line.capacity = PERIOD_ROW_TEXT * ((unsigned long long)measurement->rank + 1ull);
    line.out = (char *)malloc((size_t)line.capacity);
    line.at = 0ull;
    if (line.out == NULL)
    {
        return 0;
    }
    scriptura_text(&line, "  period over ");
    scriptura_decimal(&line, measurement->voxels, 1u);
    scriptura_text(&line, " voxels, ");
    scriptura_decimal(&line, measurement->collisions, 1u);
    scriptura_text(&line, " colliding pairs, a null band of ");
    scriptura_decimal(&line, measurement->draws, 1u);
    scriptura_text(&line, " shuffles\n");
    for (unsigned int axis = 0u; axis < measurement->rank; axis += 1u)
    {
        const PeriodAxis *const result = &measurement->axis[axis];
        scriptura_text(&line, "    axis ");
        scriptura_decimal(&line, axis, 1u);
        scriptura_text(&line, ": extent ");
        scriptura_decimal(&line, result->extent, 1u);
        scriptura_text(&line, ", lags 1 to ");
        scriptura_decimal(&line, result->lags, 1u);
        scriptura_text(&line, " over ");
        scriptura_decimal(&line, result->pairs_per_lag, 1u);
        scriptura_text(&line, " pairs each; period ");
        scriptura_decimal(&line, result->period, 1u);
        scriptura_text(&line, " (candidate ");
        scriptura_decimal(&line, result->candidate, 1u);
        scriptura_text(&line, ", agreeing ");
        scriptura_decimal(&line, result->agreement_at_candidate, 1u);
        scriptura_text(&line, " against ");
        scriptura_decimal(&line, result->agreement_beside_candidate, 1u);
        scriptura_text(&line, " beside it, ");
        scriptura_decimal(&line, result->agreement_at_double, 1u);
        scriptura_text(&line, " against ");
        scriptura_decimal(&line, result->agreement_beside_double, 1u);
        scriptura_text(&line, " beside twice it; height ");
        period_margin_text(&line, &result->margin);
        scriptura_text(&line, "; ");
        scriptura_decimal(&line, result->band_count, 1u);
        scriptura_text(&line, " shuffles reached a peak");
        if (result->band_count != 0ull)
        {
            scriptura_text(&line, ", from ");
            period_margin_text(&line, &result->band_bottom);
            scriptura_text(&line, " to ");
            period_margin_text(&line, &result->band_top);
        }
        scriptura_text(&line, ")\n");
    }
    const int written = scriptura_write(&line, file);
    free(line.out);
    return written;
}
