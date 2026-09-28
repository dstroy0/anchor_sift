// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// pi_tower_bbp.cu: the BBP sum, certificate and lanes
#include "pi_tower_internal.h"

// the run on the device: the tail's lanes reduced to the first total, then sweep after sweep of term lanes, each sweep
// one cycle of the term program over as many lanes as the device holds at once, reduced with the total carried in
int pi_tower_bbp_sum(SimResults *results, PiTowerBbp *bbp, int report, PiTowerBbpRun *run)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    memset(run, 0, sizeof(*run));
    unsigned int *inputs = NULL;
    unsigned int *buffers[2] = {NULL, NULL};
    unsigned int *index = NULL;
    unsigned int *total = NULL;
    const size_t sum_bytes = bbp->out_limbs * sizeof(unsigned int);
    const unsigned long long capacity_bytes = (bbp->lanes + 1ull) * sum_bytes;
    int ok = (cycle_record_load(&bbp->term.layout, &bbp->term.record, &error) != CYCLE_ERROR) &&
             (cycle_record_load(&bbp->tail.layout, &bbp->tail.record, &error) != CYCLE_ERROR) &&
             (cycle_record_load(&bbp->pair.layout, &bbp->pair.record, &error) != CYCLE_ERROR);
    sim_check(results, ok, "engine: the term, tail and pair programs load");
    ok = ok &&
         sim_status_check(results, cudaMalloc((void **)&inputs, bbp->lanes * bbp->in_limbs * sizeof(unsigned int)),
                          "engine: the lanes' inputs") &&
         sim_status_check(results, cudaMalloc((void **)&buffers[0], capacity_bytes), "engine: the sums") &&
         sim_status_check(results, cudaMalloc((void **)&buffers[1], capacity_bytes), "engine: the sums") &&
         sim_status_check(results, cudaMalloc((void **)&index, (bbp->lanes + 1ull) * sizeof(unsigned int)),
                          "engine: the index") &&
         sim_status_check(results, cudaMalloc((void **)&total, sum_bytes), "engine: the total") &&
         pi_tower_bbp_counted(results, index, bbp->lanes + 1ull, 1u, 0ull) &&
         pi_tower_bbp_counted(results, inputs, bbp->tail_terms, 1u, 1ull);
    if (ok != 0)
    {
        const CycleRecordRunRequest tail = {bbp->tail.record,
                                            {inputs, NULL, NULL},
                                            {bbp->tail_terms, 0ull, 0ull},
                                            NULL,
                                            bbp->tail_terms,
                                            buffers[0],
                                            &error};
        ok = cycle_record_run(&tail) != CYCLE_ERROR;
        sim_check(results, ok, "engine: the tail program runs");
    }
    unsigned int *landed =
        (ok != 0) ? pi_tower_bbp_reduce(results, bbp, buffers, index, bbp->tail_terms, &error) : NULL;
    ok = (landed != NULL) &&
         sim_status_check(results, cudaMemcpy(total, landed, sum_bytes, cudaMemcpyDeviceToDevice), "engine: the total");
    const std::chrono::steady_clock::time_point start = std::chrono::steady_clock::now();
    double next_report = 1.0;
    while ((ok != 0) && (s_pi_tower_stopped == 0) && (pi_tower_compare(pi_tower_unsigned(run->done), bbp->terms) < 0))
    {
        const PiWide left = pi_tower_difference(bbp->terms, pi_tower_unsigned(run->done));
        const unsigned long long sweep =
            (pi_tower_compare(left, pi_tower_unsigned(bbp->lanes)) > 0) ? bbp->lanes : pi_tower_word(left);
        ok = pi_tower_bbp_counted(results, inputs, sweep, bbp->in_limbs, run->done);
        const CycleRecordRunRequest terms = {
            bbp->term.record, {inputs, NULL, NULL}, {sweep, 0ull, 0ull}, NULL, sweep, buffers[0], &error};
        if ((ok != 0) && (cycle_record_run(&terms) == CYCLE_ERROR))
        {
            sim_check(results, 0, "engine: the term program runs a sweep");
            ok = 0;
        }
        ok = ok &&
             sim_status_check(
                 results, cudaMemcpy(&buffers[0][sweep * bbp->out_limbs], total, sum_bytes, cudaMemcpyDeviceToDevice),
                 "engine: the total carried in");
        landed = (ok != 0) ? pi_tower_bbp_reduce(results, bbp, buffers, index, sweep + 1ull, &error) : NULL;
        ok = (landed != NULL) &&
             sim_status_check(results, cudaMemcpy(total, landed, sum_bytes, cudaMemcpyDeviceToDevice),
                              "engine: the total");
        run->done += (ok != 0) ? sweep : 0ull;
        run->sweeps += (ok != 0) ? 1ull : 0ull;
        run->seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count();
        if ((report != 0) && (run->seconds >= next_report))
        {
            pi_tower_bbp_progress(results, bbp, run);
            next_report *= 2.0;
        }
    }
    run->finished = (ok != 0) && (pi_tower_compare(pi_tower_unsigned(run->done), bbp->terms) == 0);
    ok = ok && ((run->finished == 0) || pi_tower_bbp_read(results, bbp, total, &run->sum));
    cudaFree(inputs);
    cudaFree(buffers[0]);
    cudaFree(buffers[1]);
    cudaFree(index);
    cudaFree(total);
    cycle_record_release(bbp->term.record);
    cycle_record_release(bbp->tail.record);
    cycle_record_release(bbp->pair.record);
    bbp->term.record = NULL;
    bbp->tail.record = NULL;
    bbp->pair.record = NULL;
    return ok;
}

// the leading bits every value within the error of the sum shares: the real {16^d pi} 2^W lies strictly within E units
// of the sum S. Floor(x / 2^(W - k)) is decided wherever S - E and S + E agree on it, and neither wraps
unsigned int pi_tower_bbp_certified(const PiTowerBbp *bbp, const PiWide &sum)
{
    const PiWide error = pi_tower_bbp_error(bbp);
    const PiWide low = pi_tower_difference(sum, error);
    const PiWide high = pi_tower_sum(sum, error);
    if ((low.sign < 0) || (pi_tower_compare(high, pi_tower_power_two(bbp->fraction_bits)) >= 0))
    {
        return 0u;
    }
    unsigned int bits = bbp->fraction_bits;
    while ((bits > 0u) &&
           (pi_tower_compare(pi_tower_quotient(low, pi_tower_power_two(bbp->fraction_bits - bits)),
                             pi_tower_quotient(high, pi_tower_power_two(bbp->fraction_bits - bits))) != 0))
    {
        bits -= 1u;
    }
    return bits;
}

// the first `digits` hex digits of the sum's fraction
std::string pi_tower_bbp_hex(const PiTowerBbp *bbp, const PiWide &sum, unsigned int digits)
{
    std::string hex;
    for (unsigned int digit = 0u; digit < digits; digit += 1u)
    {
        const PiWide shifted = pi_tower_quotient(sum, pi_tower_power_two(bbp->fraction_bits - (4u * (digit + 1u))));
        hex.push_back("0123456789ABCDEF"[pi_tower_word(shifted) & 15ull]);
    }
    return hex;
}

// one run's line: its size on the engine, how it went, and the digits it certified
void pi_tower_bbp_print(SimResults *results, const PiTowerBbp *bbp, const PiTowerBbpRun *run, unsigned int certified)
{
    scriptura_text(&results->line, "    hex position ");
    pi_tower_print_decimal(&results->line, bbp->position);
    scriptura_text(&results->line, ": ");
    pi_tower_print_decimal(&results->line, bbp->terms);
    scriptura_text(&results->line, " term lanes of ");
    scriptura_decimal(&results->line, bbp->term.layout.steps, 1u);
    scriptura_text(&results->line, " steps on ");
    scriptura_decimal(&results->line, bbp->term.layout.file_limbs, 1u);
    scriptura_text(&results->line, " register limbs, ");
    scriptura_decimal(&results->line, bbp->tail_terms, 1u);
    scriptura_text(&results->line, " tail lanes, W ");
    scriptura_decimal(&results->line, bbp->fraction_bits, 1u);
    scriptura_text(&results->line, "; ");
    scriptura_decimal(&results->line, run->sweeps, 1u);
    scriptura_text(&results->line, " cycles of up to ");
    scriptura_decimal(&results->line, bbp->lanes, 1u);
    scriptura_text(&results->line, " lanes in ");
    // a run's seconds are non-negative and far below 2^64 microseconds. The floor fits the word
    sim_fraction_print(&results->line, (unsigned long long)(run->seconds * 1000000.0), 1000000ull, 3u);
    scriptura_text(&results->line, " s");
    if (run->finished != 0)
    {
        scriptura_text(&results->line, "; ");
        scriptura_decimal(&results->line, certified, 1u);
        scriptura_text(&results->line, " bits certified: ");
        scriptura_text(&results->line, pi_tower_bbp_hex(bbp, run->sum, certified / 4u).c_str());
    }
    scriptura_character(&results->line, '\n');
    sim_flush(results);
}

// the lanes a sweep holds: every thread the device keeps resident at once
unsigned long long pi_tower_bbp_lanes(void)
{
    int device = 0;
    cudaDeviceProp properties;
    if ((cudaGetDevice(&device) != cudaSuccess) || (cudaGetDeviceProperties(&properties, device) != cudaSuccess))
    {
        return 0ull;
    }
    // both counts are positive device properties
    return (unsigned long long)properties.multiProcessorCount *
           (unsigned long long)properties.maxThreadsPerMultiProcessor;
}

// the hex position whose window holds the turn at depth n, and the window's bits through it: the cell at 2^n is
// floor(alpha 2^n), and its low bits are alpha's bits n - 63 .. n, which the run from position floor((n - 64) / 4)
// holds within its first 67
PiWide pi_tower_depth_position(const PiWide &depth, unsigned int *window)
{
    const PiWide range = pi_tower_unsigned(64ull);
    if (pi_tower_compare(depth, range) <= 0)
    {
        // at most 64
        *window = (unsigned int)pi_tower_word(depth);
        return pi_tower_unsigned(0ull);
    }
    const PiWide position = pi_tower_quotient(pi_tower_difference(depth, range), pi_tower_unsigned(4ull));
    // depth - 4 d is 64 to 67
    *window =
        (unsigned int)pi_tower_word(pi_tower_difference(depth, pi_tower_product(position, pi_tower_unsigned(4ull))));
    return position;
}

// the low 64 bits of the engine's cell at depth n: the window's first `window` bits
unsigned long long pi_tower_bbp_cell(const PiTowerBbp *bbp, const PiWide &sum, unsigned int window)
{
    return pi_tower_word(pi_tower_quotient(sum, pi_tower_power_two(bbp->fraction_bits - window)));
}

// the bytes a segment's largest window holds on the device: its last, whose position and widths are the largest
static int pi_tower_segment_declared(const PiWide &position, unsigned int digits, unsigned long long lanes,
                                     unsigned long long *declared, EngineError *error)
{
    const unsigned int windows = (digits + PI_TOWER_SEGMENT_STEP - 1u) / PI_TOWER_SEGMENT_STEP;
    const PiWide last =
        pi_tower_sum(position, pi_tower_unsigned((unsigned long long)(windows - 1u) * PI_TOWER_SEGMENT_STEP));
    PiTowerBbp bbp;
    if (pi_tower_bbp_plan(&bbp, last, lanes, error) == 0)
    {
        return 0;
    }
    const unsigned long long bytes = pi_tower_bbp_bytes(&bbp);
    *declared = (bytes > *declared) ? bytes : *declared;
    pi_tower_bbp_free(&bbp);
    return 1;
}

// 15. A segment of `digits` hex digits from hex position d + 1, read as windows at d, d + 20, d + 40, ..., each its own
// run on the engine. Each window must certify PI_TOWER_BBP_CERTIFIED / 4 = 24 digits and gives the segment its first
// 20, and the 4 or more it certifies past them must be the next window's first (Bailey: "a result calculated at
// position d can be checked by repeating at position d - 1").
static PiTowerSegment pi_tower_bbp_segment(SimResults *results, const PiWide &position, unsigned int digits,
                                           unsigned long long lanes, int report, std::string *segment)
{
    PiTowerSegment result = {1, 1, 1, 1, 0u};
    EngineError error;
    memset(&error, 0, sizeof(error));
    segment->clear();
    std::string pending;
    while ((result.ran != 0) && (result.finished != 0) && (segment->size() < digits))
    {
        const PiWide window =
            pi_tower_sum(position, pi_tower_unsigned((unsigned long long)result.windows * PI_TOWER_SEGMENT_STEP));
        PiTowerBbp bbp;
        if (pi_tower_bbp_plan(&bbp, window, lanes, &error) == 0)
        {
            result.ran = 0;
            break;
        }
        PiTowerBbpRun run;
        result.ran = pi_tower_bbp_sum(results, &bbp, report, &run);
        result.finished = (result.ran != 0) && (run.finished != 0);
        const unsigned int certified = (result.finished != 0) ? pi_tower_bbp_certified(&bbp, run.sum) : 0u;
        if (report != 0)
        {
            pi_tower_bbp_print(results, &bbp, &run, certified);
        }
        if (result.finished != 0)
        {
            result.windows += 1u;
            const std::string read = pi_tower_bbp_hex(&bbp, run.sum, certified / 4u);
            result.certified = result.certified && (read.size() >= (PI_TOWER_BBP_CERTIFIED / 4u));
            result.overlapped = result.overlapped && (read.compare(0u, pending.size(), pending) == 0);
            const size_t taken = ((digits - segment->size()) < PI_TOWER_SEGMENT_STEP) ? (digits - segment->size())
                                                                                      : PI_TOWER_SEGMENT_STEP;
            segment->append(read, 0u, taken);
            pending = (read.size() > PI_TOWER_SEGMENT_STEP) ? read.substr(PI_TOWER_SEGMENT_STEP) : std::string();
        }
        pi_tower_bbp_free(&bbp);
    }
    return result;
}

// a segment's digits, 64 to a line, each line headed by the position of its first digit
static void pi_tower_segment_print(SimResults *results, const PiWide &position, const std::string &segment)
{
    for (size_t at = 0u; at < segment.size(); at += 64u)
    {
        scriptura_text(&results->line, "    ");
        pi_tower_print_decimal(&results->line,
                               pi_tower_sum(position, pi_tower_unsigned((unsigned long long)at + 1ull)));
        scriptura_text(&results->line, "  ");
        scriptura_text(&results->line, segment.substr(at, 64u).c_str());
        scriptura_character(&results->line, '\n');
        sim_flush(results);
    }
}

// 15 on the engine: the segment the request names, the job declared at its last window's bytes, and the segment printed
// 64 digits a line; where it starts at one of Bailey's positions, its head against his
void pi_tower_segment_request(SimResults *results, int count, char **arguments, const PiWide &position,
                              unsigned int digits)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    const unsigned long long lanes = pi_tower_bbp_lanes();
    unsigned long long declared = 0ull;
    const int planned = (lanes != 0ull) && pi_tower_segment_declared(position, digits, lanes, &declared, &error);
    sim_check(results, planned, "engine: keymath encodes and the scheduler lays out the term, tail and pair programs");
    if ((planned == 0) || !sim_job_submit(results, "pi_tower", count, arguments, declared))
    {
        return;
    }
    scriptura_text(&results->line, "  a segment on the engine: ");
    scriptura_decimal(&results->line, digits, 1u);
    scriptura_text(&results->line, " hex digits from position ");
    pi_tower_print_decimal(&results->line, pi_tower_sum(position, pi_tower_unsigned(1ull)));
    scriptura_text(&results->line, ", a window every ");
    scriptura_decimal(&results->line, PI_TOWER_SEGMENT_STEP, 1u);
    scriptura_character(&results->line, '\n');
    sim_flush(results);
    std::string segment;
    const PiTowerSegment result = pi_tower_bbp_segment(results, position, digits, lanes, 1, &segment);
    pi_tower_segment_print(results, position, segment);
    scriptura_text(&results->line, "    ");
    scriptura_decimal(&results->line, result.windows, 1u);
    scriptura_text(&results->line, " windows\n");
    sim_flush(results);
    sim_check(results, result.ran && result.finished && (segment.size() == digits),
              "engine: every window ran and summed all its terms");
    sim_check(results, result.certified, "every window certified at least 24 hex digits");
    sim_check(results, result.overlapped, "every window's digits past the 20 it gives are the next window's first");
    int matched = 1;
    unsigned int compared = 0u;
    for (size_t at = 0u; at < PI_TOWER_PUBLISHED_COUNT; at += 1u)
    {
        const std::string expected = s_pi_tower_published[at].digits;
        if ((pi_tower_compare(pi_tower_unsigned(s_pi_tower_published[at].position - 1ull), position) == 0) &&
            (segment.size() >= expected.size()))
        {
            scriptura_text(&results->line, "    Bailey's at position ");
            scriptura_decimal(&results->line, s_pi_tower_published[at].position, 1u);
            scriptura_text(&results->line, ": ");
            scriptura_text(&results->line, expected.c_str());
            scriptura_character(&results->line, '\n');
            matched = matched && (segment.compare(0u, expected.size(), expected) == 0);
            compared += 1u;
        }
    }
    if (compared != 0u)
    {
        sim_check(results, matched, "the segment's head is Bailey's published digits at its position");
    }
    sim_flush(results);
}
