// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// chaitin_omega_engine.cu: the engine
#include "chaitin_omega_internal.h"

int omega_engine(SimResults *results, const OmegaCounts *counts, const char *ledger, OmegaEngineReport *report,
                 std::vector<OmegaSettled> *crossed, OmegaResults *fates)
{
    omega_results_open(fates);
    memset(report, 0, sizeof(*report));
    std::vector<OmegaEngineJob> kept;
    if (ledger != NULL)
    {
        omega_engine_ledger_read(ledger, kept);
    }
    // the plan: each length in rank order, cut every OMEGA_ENGINE_JOB terms
    std::vector<OmegaEngineJob> jobs;
    for (unsigned int length = 2u; length <= counts->length; length += 1u)
    {
        const unsigned long long total = omega_count(counts, length, 0u);
        for (unsigned long long from = 0ull; from < total; from += OMEGA_ENGINE_JOB)
        {
            OmegaEngineJob job;
            job.length = length;
            job.from = from;
            job.count = ((total - from) < OMEGA_ENGINE_JOB) ? (total - from) : OMEGA_ENGINE_JOB;
            job.settled = 0ull;
            omega_results_open(&job.results);
            const OmegaEngineJob *found = NULL;
            for (const OmegaEngineJob &one : kept)
            {
                if ((one.length == length) && (one.from == from) && (one.count == job.count))
                {
                    found = &one;
                    break;
                }
            }
            if (found != NULL)
            {
                omega_merge(fates, &found->results);
                report->jobs_kept += 1ull;
                continue;
            }
            jobs.push_back(job);
        }
    }
    std::map<unsigned long long, OmegaProgram> programs;
    EngineError error;
    memset(&error, 0, sizeof(error));
    OmegaBuffer buffers[OMEGA_BUFFERS];
    memset(buffers, 0, sizeof(buffers));
    OmegaPoolExtent extent = {0ull, 0ull, 0ull, 0ull};
    std::vector<OmegaSettled> settled;
    std::vector<unsigned long long> out_sizes;
    std::vector<int> scratch;
    const size_t word = sizeof(unsigned long long);
    int ok = (omega_buffer_reserve(&buffers[OMEGA_BUFFER_COUNTS], sizeof(counts->count), 0) == 1) &&
             (omega_buffer_reserve(&buffers[OMEGA_BUFFER_TOTALS], sizeof(OmegaRoundTotals), 0) == 1);
    if (ok == 0)
    {
        sim_check(results, 0, "engine: the device holds the counts and the round's totals");
    }
    ok = ok && sim_status_check(results,
                                cudaMemcpy(buffers[OMEGA_BUFFER_COUNTS].data, counts->count, sizeof(counts->count),
                                           cudaMemcpyHostToDevice),
                                "engine: counts");
    OmegaRoundTotals *const totals = OMEGA_BUFFER(buffers, OMEGA_BUFFER_TOTALS, OmegaRoundTotals);
    size_t next_job = 0u;
    const std::chrono::steady_clock::time_point start = std::chrono::steady_clock::now();
    unsigned long long report_at = 1ull;
    while ((ok != 0) && ((next_job < jobs.size()) || (extent.live > 0ull)))
    {
        // jobs join while fewer than OMEGA_ENGINE_REFILL terms are live and the device holds them beside the rest
        while ((ok != 0) && (next_job < jobs.size()) && (extent.live < OMEGA_ENGINE_REFILL))
        {
            const int admitted =
                omega_pool_insert_job(results, buffers, &jobs[next_job], (unsigned int)next_job, &extent);
            ok = (admitted != 0);
            if (admitted != 1)
            {
                break;
            }
            next_job += 1u;
        }
        if ((ok != 0) && (extent.live == 0ull))
        {
            sim_check(results, 0, "engine: the device holds a job's terms");
            ok = 0;
        }
        const size_t live_bytes = (size_t)extent.live * word;
        if (ok != 0)
        {
            ok = (omega_buffer_reserve(&buffers[OMEGA_BUFFER_FRAMES], (size_t)extent.tokens, 0) == 1) &&
                 (omega_buffer_reserve(&buffers[OMEGA_BUFFER_INNER_FRAMES], (size_t)extent.tokens, 0) == 1) &&
                 (omega_buffer_reserve(&buffers[OMEGA_BUFFER_OUT_SIZES], live_bytes, 0) == 1) &&
                 (omega_buffer_reserve(&buffers[OMEGA_BUFFER_OUT_BASES], live_bytes, 0) == 1);
            if (ok == 0)
            {
                sim_check(results, 0, "engine: the device holds the round's survey");
            }
        }
        if (ok == 0)
        {
            break;
        }
        OmegaTerm *const terms = OMEGA_BUFFER(buffers, OMEGA_BUFFER_TERMS, OmegaTerm);
        const OmegaToken *const tokens = OMEGA_BUFFER(buffers, OMEGA_BUFFER_TOKENS, OmegaToken);
        unsigned long long *const device_out_sizes = OMEGA_BUFFER(buffers, OMEGA_BUFFER_OUT_SIZES, unsigned long long);
        unsigned long long *const out_bases = OMEGA_BUFFER(buffers, OMEGA_BUFFER_OUT_BASES, unsigned long long);
        // the terms that step this round and the widths of their records
        ok = sim_status_check(results, cudaMemset(totals, 0, sizeof(OmegaRoundTotals)), "engine: totals");
        omega_pool_survey<<<omega_pool_grid(extent.live), OMEGA_POOL_BLOCK>>>(
            terms, extent.live, tokens, OMEGA_BUFFER(buffers, OMEGA_BUFFER_FRAMES, unsigned char), device_out_sizes,
            totals);
        OmegaRoundTotals found;
        ok = ok && sim_status_check(results, cudaGetLastError(), "engine: survey") &&
             sim_status_check(results, cudaMemcpy(&found, totals, sizeof(found), cudaMemcpyDeviceToHost),
                              "engine: survey read");
        unsigned long long out_total = 0ull;
        ok = ok && omega_buffer_scan(results, &buffers[OMEGA_BUFFER_SCAN], device_out_sizes, out_bases, extent.live,
                                     &out_total);
        if (ok == 0)
        {
            break;
        }
        report->max_tokens = (found.max_tokens > report->max_tokens) ? found.max_tokens : report->max_tokens;
        OmegaRoundWidths widths;
        widths.token_bits = omega_engine_bits_of(found.max_token) + 1u;
        widths.depth_bits = omega_engine_bits_of(found.max_depth);
        widths.bound_bits = omega_engine_bits_of(found.max_bound);
        widths.token_limbs = (widths.token_bits + 31u) / 32u;
        widths.plan_limbs = (widths.depth_bits + widths.bound_bits + 2u + 31u) / 32u;
        // the record program for this round's widths
        const unsigned long long key = ((unsigned long long)widths.token_bits << 40u) |
                                       ((unsigned long long)widths.depth_bits << 20u) | widths.bound_bits;
        if (programs.find(key) == programs.end())
        {
            OmegaProgram program;
            program.token_bits = widths.token_bits;
            program.depth_bits = widths.depth_bits;
            program.bound_bits = widths.bound_bits;
            if (omega_program_load(&program, &error) == 0)
            {
                sim_check(results, 0, "engine: the reduct program encodes and loads for the round's widths");
                ok = 0;
                break;
            }
            programs[key] = program;
        }
        const OmegaProgram *const program = &programs[key];
        const unsigned int out_limbs = program->layout.out_limbs;
        // the round's buffers; while the device cannot hold them, the stepping term with the largest reduct is parked
        // as outgrown and the reducts laid out again without it
        const OmegaBufferName round_buffers[19] = {
            OMEGA_BUFFER_PACKED,       OMEGA_BUFFER_PLANS,       OMEGA_BUFFER_INDEX,       OMEGA_BUFFER_OUT,
            OMEGA_BUFFER_REDUCTS,      OMEGA_BUFFER_REDUCT_ENDS, OMEGA_BUFFER_KEPT_TERMS,  OMEGA_BUFFER_KEPT_TOKENS,
            OMEGA_BUFFER_KEPT_STORED,  OMEGA_BUFFER_KEPT_ENDS,   OMEGA_BUFFER_SETTLED,     OMEGA_BUFFER_PLACES,
            OMEGA_BUFFER_PLACE_BASES,  OMEGA_BUFFER_TOKEN_SIZES, OMEGA_BUFFER_TOKEN_BASES, OMEGA_BUFFER_STORED_SIZES,
            OMEGA_BUFFER_STORED_BASES, OMEGA_BUFFER_END_SIZES,   OMEGA_BUFFER_END_BASES};
        int reserved = 0;
        while ((ok != 0) && (reserved == 0))
        {
            const unsigned long long lanes = (out_total < OMEGA_ENGINE_SWEEP) ? out_total : OMEGA_ENGINE_SWEEP;
            const size_t limb = sizeof(unsigned int);
            const size_t bytes[19] = {(size_t)extent.tokens * widths.token_limbs * limb,
                                      (size_t)out_total * widths.plan_limbs * limb,
                                      (size_t)out_total * 2u * limb,
                                      (size_t)lanes * out_limbs * limb,
                                      (size_t)out_total * sizeof(OmegaToken),
                                      (size_t)(out_total + extent.live) * word,
                                      (size_t)extent.live * sizeof(OmegaTerm),
                                      (size_t)out_total * sizeof(OmegaToken),
                                      (size_t)(extent.stored + out_total) * sizeof(OmegaToken),
                                      (size_t)(extent.ends + out_total + extent.live) * word,
                                      (size_t)extent.live * sizeof(OmegaSettled),
                                      live_bytes,
                                      live_bytes,
                                      live_bytes,
                                      live_bytes,
                                      live_bytes,
                                      live_bytes,
                                      live_bytes,
                                      live_bytes};
            reserved = 1;
            for (unsigned int buffer = 0u; buffer < 19u; buffer += 1u)
            {
                const int one = omega_buffer_reserve(&buffers[round_buffers[buffer]], bytes[buffer], 0);
                if (one < 0)
                {
                    sim_check(results, 0, "engine: a round's buffer is held");
                    ok = 0;
                }
                if (one != 1)
                {
                    reserved = 0;
                    break;
                }
            }
            if ((ok == 0) || (reserved != 0))
            {
                continue;
            }
            out_sizes.resize((size_t)extent.live);
            ok = sim_status_check(results,
                                  cudaMemcpy(out_sizes.data(), device_out_sizes, live_bytes, cudaMemcpyDeviceToHost),
                                  "engine: reduct sizes");
            size_t largest = 0u;
            for (size_t at = 1u; at < out_sizes.size(); at += 1u)
            {
                largest = (out_sizes[at] > out_sizes[largest]) ? at : largest;
            }
            if ((ok != 0) && (out_sizes[largest] == 0ull))
            {
                sim_check(results, 0, "engine: the device holds a round once every reduct is parked");
                ok = 0;
            }
            const int grew = OMEGA_GREW;
            const unsigned long long none = 0ull;
            ok =
                ok &&
                sim_status_check(results, cudaMemcpy(&terms[largest].fate, &grew, sizeof(grew), cudaMemcpyHostToDevice),
                                 "engine: park") &&
                sim_status_check(results,
                                 cudaMemcpy(&device_out_sizes[largest], &none, sizeof(none), cudaMemcpyHostToDevice),
                                 "engine: park") &&
                omega_buffer_scan(results, &buffers[OMEGA_BUFFER_SCAN], device_out_sizes, out_bases, extent.live,
                                  &out_total);
            report->parked += (ok != 0) ? 1ull : 0ull;
        }
        if ((ok != 0) && (extent.tokens > OMEGA_ENGINE_INDEX_MAX))
        {
            sim_check(results, 0, "engine: every token a round reads sits within the engine's 32-bit index");
            ok = 0;
        }
        if (ok == 0)
        {
            break;
        }
        unsigned int *const packed = OMEGA_BUFFER(buffers, OMEGA_BUFFER_PACKED, unsigned int);
        unsigned int *const plans = OMEGA_BUFFER(buffers, OMEGA_BUFFER_PLANS, unsigned int);
        unsigned int *const index = OMEGA_BUFFER(buffers, OMEGA_BUFFER_INDEX, unsigned int);
        unsigned int *const out = OMEGA_BUFFER(buffers, OMEGA_BUFFER_OUT, unsigned int);
        OmegaToken *const reducts = OMEGA_BUFFER(buffers, OMEGA_BUFFER_REDUCTS, OmegaToken);
        if (out_total > 0ull)
        {
            omega_pool_pack<<<omega_pool_grid(extent.tokens), OMEGA_POOL_BLOCK>>>(tokens, extent.tokens, widths,
                                                                                  packed);
            omega_pool_place<<<omega_pool_grid(extent.live), OMEGA_POOL_BLOCK>>>(
                terms, extent.live, tokens, out_bases, OMEGA_BUFFER(buffers, OMEGA_BUFFER_FRAMES, unsigned char),
                OMEGA_BUFFER(buffers, OMEGA_BUFFER_INNER_FRAMES, unsigned char), widths, plans, index);
            ok = sim_status_check(results, cudaGetLastError(), "engine: pack and lay out");
            // the sweeps: every token of the pool is member 0, and each sweep's plans member 1 from its first lane
            for (unsigned long long first = 0ull; (ok != 0) && (first < out_total); first += OMEGA_ENGINE_SWEEP)
            {
                const unsigned long long lanes =
                    ((out_total - first) < OMEGA_ENGINE_SWEEP) ? (out_total - first) : OMEGA_ENGINE_SWEEP;
                const CycleRecordRunRequest run = {program->record,
                                                   {packed, &plans[first * widths.plan_limbs], NULL},
                                                   {extent.tokens, lanes, 0ull},
                                                   &index[2ull * first],
                                                   lanes,
                                                   out,
                                                   &error};
                if (cycle_record_run(&run) == CYCLE_ERROR)
                {
                    sim_check(results, 0, "engine: the record machine runs the round's sweep");
                    ok = 0;
                    break;
                }
                omega_pool_unpack<<<omega_pool_grid(lanes), OMEGA_POOL_BLOCK>>>(
                    out, lanes, out_limbs, program->out_offset, program->out_bits, &reducts[first], totals);
                ok = sim_status_check(results, cudaGetLastError(), "engine: reducts");
                report->sweeps += 1ull;
                report->records += lanes;
            }
            unsigned int unread = 0u;
            ok = ok &&
                 sim_status_check(results, cudaMemcpy(&unread, &totals->unread, sizeof(unread), cudaMemcpyDeviceToHost),
                                  "engine: reducts read");
            if ((ok != 0) && (unread != 0u))
            {
                sim_check(results, 0, "engine: every reduct token is read back whole");
                ok = 0;
            }
            omega_pool_watch<<<omega_pool_grid(extent.live), OMEGA_POOL_BLOCK>>>(
                terms, extent.live, reducts, out_bases, OMEGA_BUFFER(buffers, OMEGA_BUFFER_STORED, OmegaToken),
                OMEGA_BUFFER(buffers, OMEGA_BUFFER_ENDS, unsigned long long),
                OMEGA_BUFFER(buffers, OMEGA_BUFFER_REDUCT_ENDS, unsigned long long));
            ok = ok && sim_status_check(results, cudaGetLastError(), "engine: watch");
        }
        if (ok == 0)
        {
            break;
        }
        report->rounds += 1ull;
        // the settled leave the pool into their jobs; a job whose every term settled is written to the ledger
        omega_pool_settled<<<omega_pool_grid(extent.live), OMEGA_POOL_BLOCK>>>(
            terms, extent.live, OMEGA_BUFFER(buffers, OMEGA_BUFFER_SETTLED, OmegaSettled), totals);
        unsigned long long settled_count = 0ull;
        ok = sim_status_check(results, cudaGetLastError(), "engine: settled") &&
             sim_status_check(
                 results, cudaMemcpy(&settled_count, &totals->settled, sizeof(settled_count), cudaMemcpyDeviceToHost),
                 "engine: settled count");
        settled.resize((size_t)settled_count);
        ok = ok && ((settled_count == 0ull) ||
                    sim_status_check(results,
                                     cudaMemcpy(settled.data(), buffers[OMEGA_BUFFER_SETTLED].data,
                                                (size_t)settled_count * sizeof(OmegaSettled), cudaMemcpyDeviceToHost),
                                     "engine: settled read"));
        for (size_t at = 0u; (ok != 0) && (at < settled.size()); at += 1u)
        {
            const OmegaSettled *const one = &settled[at];
            report->max_steps = (one->steps > report->max_steps) ? one->steps : report->max_steps;
            OmegaEngineJob *const job = &jobs[one->job];
            omega_engine_settle(counts, job, one, scratch, crossed);
            if (job->settled == job->count)
            {
                if ((ledger != NULL) && (omega_engine_ledger_write(ledger, job) == 0))
                {
                    sim_check(results, 0, "engine: the ledger takes each finished job");
                    ok = 0;
                }
                omega_merge(fates, &job->results);
                report->jobs_run += 1ull;
            }
        }
        // the kept terms move into the other buffer of each pair, in pool order
        unsigned long long *const places = OMEGA_BUFFER(buffers, OMEGA_BUFFER_PLACES, unsigned long long);
        unsigned long long *const token_sizes = OMEGA_BUFFER(buffers, OMEGA_BUFFER_TOKEN_SIZES, unsigned long long);
        unsigned long long *const stored_sizes = OMEGA_BUFFER(buffers, OMEGA_BUFFER_STORED_SIZES, unsigned long long);
        unsigned long long *const end_sizes = OMEGA_BUFFER(buffers, OMEGA_BUFFER_END_SIZES, unsigned long long);
        unsigned long long *const place_bases = OMEGA_BUFFER(buffers, OMEGA_BUFFER_PLACE_BASES, unsigned long long);
        unsigned long long *const token_bases = OMEGA_BUFFER(buffers, OMEGA_BUFFER_TOKEN_BASES, unsigned long long);
        unsigned long long *const stored_bases = OMEGA_BUFFER(buffers, OMEGA_BUFFER_STORED_BASES, unsigned long long);
        unsigned long long *const end_bases = OMEGA_BUFFER(buffers, OMEGA_BUFFER_END_BASES, unsigned long long);
        omega_pool_kept_sizes<<<omega_pool_grid(extent.live), OMEGA_POOL_BLOCK>>>(terms, extent.live, places,
                                                                                  token_sizes, stored_sizes, end_sizes);
        OmegaPoolExtent kept_extent = {0ull, 0ull, 0ull, 0ull};
        ok = ok && sim_status_check(results, cudaGetLastError(), "engine: kept sizes") &&
             omega_buffer_scan(results, &buffers[OMEGA_BUFFER_SCAN], places, place_bases, extent.live,
                               &kept_extent.live) &&
             omega_buffer_scan(results, &buffers[OMEGA_BUFFER_SCAN], token_sizes, token_bases, extent.live,
                               &kept_extent.tokens) &&
             omega_buffer_scan(results, &buffers[OMEGA_BUFFER_SCAN], stored_sizes, stored_bases, extent.live,
                               &kept_extent.stored) &&
             omega_buffer_scan(results, &buffers[OMEGA_BUFFER_SCAN], end_sizes, end_bases, extent.live,
                               &kept_extent.ends);
        if (ok == 0)
        {
            break;
        }
        const unsigned long long keep_blocks = (extent.live < OMEGA_POOL_GRID_MAX) ? extent.live : OMEGA_POOL_GRID_MAX;
        // at most OMEGA_POOL_GRID_MAX blocks, which an unsigned int holds
        omega_pool_keep<<<(unsigned int)keep_blocks, 128u>>>(
            terms, extent.live, reducts, OMEGA_BUFFER(buffers, OMEGA_BUFFER_STORED, OmegaToken),
            OMEGA_BUFFER(buffers, OMEGA_BUFFER_ENDS, unsigned long long), place_bases, token_bases, stored_bases,
            end_bases, OMEGA_BUFFER(buffers, OMEGA_BUFFER_KEPT_TERMS, OmegaTerm),
            OMEGA_BUFFER(buffers, OMEGA_BUFFER_KEPT_TOKENS, OmegaToken),
            OMEGA_BUFFER(buffers, OMEGA_BUFFER_KEPT_STORED, OmegaToken),
            OMEGA_BUFFER(buffers, OMEGA_BUFFER_KEPT_ENDS, unsigned long long));
        ok = sim_status_check(results, cudaGetLastError(), "engine: keep") &&
             sim_status_check(results, cudaDeviceSynchronize(), "engine: keep");
        omega_buffer_swap(&buffers[OMEGA_BUFFER_TERMS], &buffers[OMEGA_BUFFER_KEPT_TERMS]);
        omega_buffer_swap(&buffers[OMEGA_BUFFER_TOKENS], &buffers[OMEGA_BUFFER_KEPT_TOKENS]);
        omega_buffer_swap(&buffers[OMEGA_BUFFER_STORED], &buffers[OMEGA_BUFFER_KEPT_STORED]);
        omega_buffer_swap(&buffers[OMEGA_BUFFER_ENDS], &buffers[OMEGA_BUFFER_KEPT_ENDS]);
        extent = kept_extent;
        if (report->rounds == report_at)
        {
            const double seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count();
            scriptura_text(&results->line, "  round ");
            scriptura_decimal(&results->line, report->rounds, 1u);
            scriptura_text(&results->line, ": ");
            scriptura_decimal(&results->line, extent.live, 1u);
            scriptura_text(&results->line, " live, ");
            scriptura_decimal(&results->line, report->jobs_run, 1u);
            scriptura_text(&results->line, " of ");
            scriptura_decimal(&results->line, jobs.size(), 1u);
            scriptura_text(&results->line, " jobs done, ");
            scriptura_decimal(&results->line, report->records, 1u);
            scriptura_text(&results->line, " records swept, the largest term ");
            scriptura_decimal(&results->line, report->max_tokens, 1u);
            scriptura_text(&results->line, " tokens, ");
            scriptura_decimal(&results->line, (unsigned long long)(seconds * 1000.0), 1u);
            scriptura_text(&results->line, " ms\n");
            sim_flush(results);
            report_at *= 2ull;
        }
    }
    for (std::map<unsigned long long, OmegaProgram>::iterator one = programs.begin(); one != programs.end(); ++one)
    {
        omega_program_free(&one->second);
    }
    for (unsigned int buffer = 0u; buffer < (unsigned int)OMEGA_BUFFERS; buffer += 1u)
    {
        omega_buffer_release(&buffers[buffer]);
    }
    return ok;
}
