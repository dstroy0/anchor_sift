// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// noise_detector_lines_summary.cu: line and plane noise summarized
#include "noise_detector_internal.h"

static const char *const NOISE_LINE_NAMES[NOISE_LINE_KINDS] = {"row", "column", "plane"};

void noise_exact_wide(AnchorExactInteger *value, const NoiseWide *wide)
{
    anchor_exact_zero(value);
    value->limb[0] = (uint32_t)(wide->low & 0xFFFFFFFFull);
    value->limb[1] = (uint32_t)(wide->low >> 32u);
    value->limb[2] = (uint32_t)(wide->high & 0xFFFFFFFFull);
    value->limb[3] = (uint32_t)(wide->high >> 32u);
    value->sign = ((wide->low | wide->high) != 0ull) ? 1 : 0;
}

// the lines' summed squares against their members' squares, in thousandths rounded down; 0 where nothing was summed
static int noise_line_per_mille(const NoiseWide *line_squares, unsigned long long member_squares,
                                unsigned long long *per_mille)
{
    if (member_squares == 0ull)
    {
        return 0;
    }
    AnchorExactInteger numerator;
    AnchorExactInteger denominator;
    AnchorExactInteger factor;
    AnchorExactInteger quotient;
    AnchorExactInteger remainder;
    noise_exact_wide(&numerator, line_squares);
    noise_exact_word(&factor, 1000ull);
    noise_exact_word(&denominator, member_squares);
    int ok = (anchor_exact_multiply(&numerator, &factor, &numerator) == ANCHOR_EXACT_OK) &&
             (anchor_exact_divide(&numerator, &denominator, &quotient, &remainder) == ANCHOR_EXACT_OK);
    for (unsigned int limb = 2u; ok && (limb < ANCHOR_EXACT_LIMBS); limb += 1u)
    {
        ok = quotient.limb[limb] == 0u;
    }
    *per_mille = ok ? (((unsigned long long)quotient.limb[1] << 32u) | quotient.limb[0]) : 0ull;
    return ok;
}

static void noise_lines_summary(const char *name, const NoiseLineCell cells[NOISE_LINE_CELLS])
{
    printf("  %-24s", name);
    unsigned long long counted[NOISE_LINE_KINDS];
    for (unsigned int kind = 0u; kind < NOISE_LINE_KINDS; kind += 1u)
    {
        NoiseLineCell pooled;
        memset(&pooled, 0, sizeof(pooled));
        for (unsigned int level_bin = NOISE_SUMMARY_FIRST_BIN; level_bin <= NOISE_SUMMARY_LAST_BIN; level_bin += 1u)
        {
            const NoiseLineCell *const cell = &cells[(kind * NOISE_LEVEL_BINS) + level_bin];
            pooled.lines += cell->lines;
            pooled.member_squares += cell->member_squares;
            noise_wide_add(&pooled.line_squares, cell->line_squares.low, cell->line_squares.high);
        }
        counted[kind] = pooled.lines;
        unsigned long long per_mille = 0ull;
        if (noise_line_per_mille(&pooled.line_squares, pooled.member_squares, &per_mille))
        {
            printf(" %9llu", per_mille);
        }
        else
        {
            printf(" %9s", "-");
        }
    }
    printf("   lines: %llu, %llu, %llu\n", counted[NOISE_LINE_ROWS], counted[NOISE_LINE_COLUMNS],
           counted[NOISE_LINE_PLANES]);
    fflush(stdout);
}

// scale times numerator over denominator, signed and rounded toward zero; 0 where the denominator is 0 or the
// quotient's magnitude reaches 2^63
static int noise_exact_ratio(const AnchorExactInteger *numerator, const AnchorExactInteger *denominator,
                             unsigned long long scale, long long *ratio)
{
    if (denominator->sign == 0)
    {
        return 0;
    }
    AnchorExactInteger scaled;
    AnchorExactInteger factor;
    AnchorExactInteger quotient;
    AnchorExactInteger remainder;
    noise_exact_word(&factor, scale);
    int ok = (anchor_exact_multiply(numerator, &factor, &scaled) == ANCHOR_EXACT_OK) &&
             (anchor_exact_divide(&scaled, denominator, &quotient, &remainder) == ANCHOR_EXACT_OK);
    for (unsigned int limb = 2u; ok && (limb < ANCHOR_EXACT_LIMBS); limb += 1u)
    {
        ok = quotient.limb[limb] == 0u;
    }
    const unsigned long long magnitude = ok ? (((unsigned long long)quotient.limb[1] << 32u) | quotient.limb[0]) : 0ull;
    ok = ok && (magnitude <= 0x7FFFFFFFFFFFFFFFull);
    // the magnitude is below 2^63. It converts to long long exactly; the sign is held apart
    *ratio = ok ? ((long long)magnitude * (long long)quotient.sign) : 0ll;
    return ok;
}

void noise_planes_readings(const NoisePlanePool *pool, long long readings[NOISE_TWO_WAY_READINGS],
                           int valid[NOISE_TWO_WAY_READINGS])
{
    const unsigned long long height = pool->height;
    const unsigned long long width = pool->width;
    AnchorExactInteger residual;
    AnchorExactInteger factor;
    AnchorExactInteger row_part;
    AnchorExactInteger column_part;
    AnchorExactInteger plane_part;
    AnchorExactInteger counted;
    noise_exact_word(&factor, width - 1ull);
    int ok = (anchor_exact_subtract(&pool->spread, &pool->rows, &residual) == ANCHOR_EXACT_OK) &&
             (anchor_exact_subtract(&residual, &pool->columns, &residual) == ANCHOR_EXACT_OK) &&
             (anchor_exact_multiply(&pool->rows, &factor, &row_part) == ANCHOR_EXACT_OK);
    noise_exact_word(&factor, height - 1ull);
    ok = ok && (anchor_exact_multiply(&pool->columns, &factor, &column_part) == ANCHOR_EXACT_OK);
    noise_exact_word(&factor, (height - 1ull) * (width - 1ull));
    ok = ok && (anchor_exact_multiply(&pool->plane_squares, &factor, &plane_part) == ANCHOR_EXACT_OK) &&
         (anchor_exact_subtract(&plane_part, &row_part, &plane_part) == ANCHOR_EXACT_OK) &&
         (anchor_exact_subtract(&plane_part, &column_part, &plane_part) == ANCHOR_EXACT_OK) &&
         (anchor_exact_add(&plane_part, &residual, &plane_part) == ANCHOR_EXACT_OK) &&
         (anchor_exact_add(&plane_part, &residual, &plane_part) == ANCHOR_EXACT_OK);
    // the planes' voxels are the sample's frame pairs times its voxels, which the sample's bound holds in a word
    noise_exact_word(&counted, height * width * pool->planes);
    ok = ok && (anchor_exact_multiply(&counted, &factor, &counted) == ANCHOR_EXACT_OK);
    const AnchorExactInteger *const numerators[NOISE_TWO_WAY_READINGS] = {&row_part, &column_part, &plane_part,
                                                                          &residual};
    const AnchorExactInteger *const denominators[NOISE_TWO_WAY_READINGS] = {&residual, &residual, &residual, &counted};
    const unsigned long long scales[NOISE_TWO_WAY_READINGS] = {1000ull, 1000ull, 1000ull, 1ull};
    for (unsigned int ratio = 0u; ratio < NOISE_TWO_WAY_READINGS; ratio += 1u)
    {
        readings[ratio] = 0ll;
        valid[ratio] = ok && noise_exact_ratio(numerators[ratio], denominators[ratio], scales[ratio], &readings[ratio]);
    }
}

static void noise_planes_summary(const NoisePlanePool *pool)
{
    long long readings[NOISE_TWO_WAY_READINGS];
    int valid[NOISE_TWO_WAY_READINGS];
    noise_planes_readings(pool, readings, valid);
    const char *const said[NOISE_TWO_WAY_READINGS] = {"within each plane: rows", "columns", "plane", "independent"};
    printf("  %-24s", "");
    for (unsigned int ratio = 0u; ratio < NOISE_TWO_WAY_READINGS; ratio += 1u)
    {
        if (valid[ratio] != 0)
        {
            printf(" %s %lld", said[ratio], readings[ratio]);
        }
        else
        {
            printf(" %s -", said[ratio]);
        }
    }
    printf("\n");
    fflush(stdout);
}

// The static layout's three shared variances against the independent part s, per mille and signed (each 0 where
// nothing is shared), then s in thousandths of a lane unit squared. With each kind's excess A its squared sums less T,
// D_plane = K_plane - K_row - K_column: var_plane = (A_plane - A_row - A_column) / D_plane, var_row = A_row / K_row -
// var_plane, var_column = A_column / K_column - var_plane, and s = T / M - var_row - var_column - var_plane, each
// carried over the common denominator L = M K_row K_column D_plane so nothing is rounded before the last division.
void noise_static_readings(const NoiseStaticPool *still, long long readings[NOISE_STATIC_READINGS],
                           int valid[NOISE_STATIC_READINGS])
{
    AnchorExactInteger squares;
    AnchorExactInteger members;
    AnchorExactInteger row_pairs;
    AnchorExactInteger column_pairs;
    AnchorExactInteger plane_pairs;
    AnchorExactInteger row_excess;
    AnchorExactInteger column_excess;
    AnchorExactInteger plane_excess;
    noise_exact_word(&squares, still->squares);
    noise_exact_word(&members, still->members);
    noise_exact_word(&row_pairs, still->row_pairs);
    noise_exact_word(&column_pairs, still->column_pairs);
    noise_exact_word(&plane_pairs, still->plane_pairs);
    noise_exact_wide(&row_excess, &still->row_squares);
    noise_exact_wide(&column_excess, &still->column_squares);
    noise_exact_wide(&plane_excess, &still->plane_squares);
    // plane_pairs becomes D_plane, and plane_excess the plane's excess less the rows' and the columns'
    int ok = (anchor_exact_subtract(&row_excess, &squares, &row_excess) == ANCHOR_EXACT_OK) &&
             (anchor_exact_subtract(&column_excess, &squares, &column_excess) == ANCHOR_EXACT_OK) &&
             (anchor_exact_subtract(&plane_excess, &squares, &plane_excess) == ANCHOR_EXACT_OK) &&
             (anchor_exact_subtract(&plane_excess, &row_excess, &plane_excess) == ANCHOR_EXACT_OK) &&
             (anchor_exact_subtract(&plane_excess, &column_excess, &plane_excess) == ANCHOR_EXACT_OK) &&
             (anchor_exact_subtract(&plane_pairs, &row_pairs, &plane_pairs) == ANCHOR_EXACT_OK) &&
             (anchor_exact_subtract(&plane_pairs, &column_pairs, &plane_pairs) == ANCHOR_EXACT_OK);
    // var_plane L, then A_row M K_column D_plane and A_column M K_row D_plane, then s L and L
    AnchorExactInteger plane_part;
    AnchorExactInteger row_part;
    AnchorExactInteger column_part;
    AnchorExactInteger independent;
    AnchorExactInteger common;
    ok = ok && (anchor_exact_multiply(&plane_excess, &members, &plane_part) == ANCHOR_EXACT_OK) &&
         (anchor_exact_multiply(&plane_part, &row_pairs, &plane_part) == ANCHOR_EXACT_OK) &&
         (anchor_exact_multiply(&plane_part, &column_pairs, &plane_part) == ANCHOR_EXACT_OK) &&
         (anchor_exact_multiply(&row_excess, &members, &row_part) == ANCHOR_EXACT_OK) &&
         (anchor_exact_multiply(&row_part, &column_pairs, &row_part) == ANCHOR_EXACT_OK) &&
         (anchor_exact_multiply(&row_part, &plane_pairs, &row_part) == ANCHOR_EXACT_OK) &&
         (anchor_exact_multiply(&column_excess, &members, &column_part) == ANCHOR_EXACT_OK) &&
         (anchor_exact_multiply(&column_part, &row_pairs, &column_part) == ANCHOR_EXACT_OK) &&
         (anchor_exact_multiply(&column_part, &plane_pairs, &column_part) == ANCHOR_EXACT_OK) &&
         (anchor_exact_multiply(&row_pairs, &column_pairs, &common) == ANCHOR_EXACT_OK) &&
         (anchor_exact_multiply(&common, &plane_pairs, &common) == ANCHOR_EXACT_OK) &&
         (anchor_exact_multiply(&common, &squares, &independent) == ANCHOR_EXACT_OK) &&
         (anchor_exact_subtract(&independent, &row_part, &independent) == ANCHOR_EXACT_OK) &&
         (anchor_exact_subtract(&independent, &column_part, &independent) == ANCHOR_EXACT_OK) &&
         (anchor_exact_add(&independent, &plane_part, &independent) == ANCHOR_EXACT_OK) &&
         (anchor_exact_multiply(&common, &members, &common) == ANCHOR_EXACT_OK) &&
         (anchor_exact_subtract(&row_part, &plane_part, &row_part) == ANCHOR_EXACT_OK) &&
         (anchor_exact_subtract(&column_part, &plane_part, &column_part) == ANCHOR_EXACT_OK);
    const AnchorExactInteger *const numerators[NOISE_STATIC_READINGS] = {&row_part, &column_part, &plane_part,
                                                                         &independent};
    const AnchorExactInteger *const denominators[NOISE_STATIC_READINGS] = {&independent, &independent, &independent,
                                                                           &common};
    for (unsigned int measurement = 0u; measurement < NOISE_STATIC_READINGS; measurement += 1u)
    {
        readings[measurement] = 0ll;
        valid[measurement] = ok && noise_exact_ratio(numerators[measurement], denominators[measurement], 1000ull,
                                                     &readings[measurement]);
    }
}

static void noise_static_summary(const NoiseStaticPool *still)
{
    long long readings[NOISE_STATIC_READINGS];
    int valid[NOISE_STATIC_READINGS];
    noise_static_readings(still, readings, valid);
    const char *const said[NOISE_STATIC_READINGS] = {"rows", "columns", "plane", "independent"};
    printf("  %-24s static, means up to %llu, %llu voxel-frame pairs:", "", still->ceiling, still->members);
    for (unsigned int measurement = 0u; measurement < NOISE_STATIC_READINGS; measurement += 1u)
    {
        if (valid[measurement] != 0)
        {
            printf(" %s %lld", said[measurement], readings[measurement]);
        }
        else
        {
            printf(" %s -", said[measurement]);
        }
    }
    printf("\n");
    fflush(stdout);
}

static int noise_lines_rows(FILE *table, const char *name, const NoiseLineCell cells[NOISE_LINE_CELLS])
{
    int ok = 1;
    for (unsigned int kind = 0u; ok && (kind < NOISE_LINE_KINDS); kind += 1u)
    {
        for (unsigned int level_bin = 0u; ok && (level_bin < NOISE_LEVEL_BINS); level_bin += 1u)
        {
            const NoiseLineCell *const cell = &cells[(kind * NOISE_LEVEL_BINS) + level_bin];
            if (cell->lines == 0ull)
            {
                continue;
            }
            ok = fprintf(table, "%s\t%s\t%u\t%llu\t%llu\t%llu\t%llu\t%llu\n", name, NOISE_LINE_NAMES[kind],
                         level_bin << (NOISE_LEVEL_BIN_SHIFT - 1u), cell->lines, cell->members, cell->member_squares,
                         cell->line_squares.high, cell->line_squares.low) > 0;
        }
    }
    return ok;
}

extern "C" long noise_lines_set(const NoiseSetRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return NOISE_DETECTOR_ERROR;
    }
    EngineError *const error = request->error;
    char path[ENGINE_PATH_CAPACITY];
    const int written = (request->set != NULL) ? snprintf(path, sizeof(path), "%s/noise_lines.tsv", request->set) : -1;
    const int named = (written > 0) && ((size_t)written < sizeof(path));
    FILE *const table = named ? fopen(path, "wb") : NULL;
    char plane_path[ENGINE_PATH_CAPACITY];
    const int plane_written =
        (request->set != NULL) ? snprintf(plane_path, sizeof(plane_path), "%s/noise_planes.tsv", request->set) : -1;
    const int plane_named = (plane_written > 0) && ((size_t)plane_written < sizeof(plane_path));
    FILE *const plane_table = plane_named ? fopen(plane_path, "wb") : NULL;
    int ok = NOISE_DETECTOR_CHECK(named && plane_named && (request->samples != NULL) && (request->load != NULL),
                                  request, error, ENGINE_ERROR_REQUEST) &&
             NOISE_DETECTOR_IO(table != NULL, path, error) &&
             NOISE_DETECTOR_IO(fprintf(table, "sample\tline\tlowest_mean\tlines\tmembers\tmember_squares"
                                              "\tline_squares_high\tline_squares_low\n") > 0,
                               table, error) &&
             NOISE_DETECTOR_IO(plane_table != NULL, plane_path, error) &&
             NOISE_DETECTOR_IO(fprintf(plane_table, "sample\tframe\tz\tmembers\tlevel\tplane_sum\tplane_squares"
                                                    "\trow_squares\tcolumn_squares\tstatic_members\tstatic_sum"
                                                    "\tstatic_squares\tstatic_level\n") > 0,
                               plane_table, error);
    printf("  lines: each frame difference summed along a row (x), a column (y) and a whole z plane, the sum squared,"
           " in bins of 8 by the line's mean\n");
    printf("  the lines' squared sums against their members' squares summed, per mille, means 40 to 199 (independent"
           " noise holds 1000; an offset shared along the line raises it):\n");
    printf("  then every plane as a two-way layout, rows by columns: rows 1 + W var_row / s, columns 1 + H var_col / s"
           " and the plane 1 + N var_plane / s, per mille (1000 where nothing is shared), and s, the independent"
           " variance of a voxel's frame difference, in lane units squared\n");
    printf("  then the static voxels alone (the dimmest quarter by mean of those that change, never touch either end"
           " of the lane, and hold a mean square frame difference within 4 times their mean plus 32) as an unbalanced"
           " layout: var_row, var_col and var_plane against s, per mille (0 where nothing is shared), and s in"
           " thousandths of a lane unit squared\n");
    printf("  %-24s %9s %9s %9s\n", "", "rows", "columns", "planes");
    NoiseLineCell *const cells = (NoiseLineCell *)malloc((size_t)NOISE_LINE_CELLS * sizeof(NoiseLineCell));
    ok = ok && NOISE_DETECTOR_CHECK(cells != NULL, &cells, error, ENGINE_ERROR_RESOURCE);
    // four exact integers, held apart from the stack
    NoisePlanePool *const pool = (NoisePlanePool *)malloc(sizeof(NoisePlanePool));
    ok = ok && NOISE_DETECTOR_CHECK(pool != NULL, &pool, error, ENGINE_ERROR_RESOURCE);
    NoiseStaticPool still;
    memset(&still, 0, sizeof(still));
    const unsigned long long began = engine_clock_microseconds();
    for (unsigned int sample = 0u; ok && (sample < request->count); sample += 1u)
    {
        const char *const name = request->samples[sample];
        unsigned long long extent[4] = {0ull, 0ull, 0ull, 0ull};
        unsigned short *volume = NULL;
        ok = NOISE_DETECTOR_CHECK(request->load(request->set, name, extent, &volume, error) == 0L, name, error,
                                  ENGINE_ERROR_REQUEST) &&
             (noise_lines_sample(volume, extent, cells, pool, &still, plane_table, name, error) == 0L);
        free(volume);
        ok = ok && NOISE_DETECTOR_IO(noise_lines_rows(table, name, cells) != 0, table, error);
        if (ok != 0)
        {
            noise_lines_summary(name, cells);
            noise_planes_summary(pool);
            noise_static_summary(&still);
        }
    }
    free(cells);
    free(pool);
    if (table != NULL)
    {
        ok = NOISE_DETECTOR_IO(fclose(table) == 0, path, error) && ok;
    }
    if (plane_table != NULL)
    {
        ok = NOISE_DETECTOR_IO(fclose(plane_table) == 0, plane_path, error) && ok;
    }
    if (ok != 0)
    {
        printf("  lines: %u samples in %llu ms; every sum is in %s, and every plane's in %s\n", request->count,
               (engine_clock_microseconds() - began) / 1000ull, path, plane_path);
    }
    return (ok != 0) ? 0L : NOISE_DETECTOR_ERROR;
}
