// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// The record machine's lane as VHDL held to the host oracle word for word (engine_table.md item 11(f), VHDL a
// language of the register lane). record_host_test's programs, drawn from the same stream in the same order, are
// imprinted, laid and run by cycle_record_run_host; each is written as VHDL by EmitVhdl (emit/rulesets/vhdl.krs),
// analyzed and run by GHDL under record_vhdl_bench.vhd over a memory image laid as the device lays its launch
// (record_image.h), its lanes run by the emitted cycle_program_unit as the device's resident kernel runs them, and its
// records compared with the host's word for word; synthesis takes the program unit whole. Its lines give the same
// input digests as the host test's. A program whose lane the emitter does not write is counted as not held, not as
// held or failed.
// Where a construction set is given, each program's lane is refined by it (engine_table M23): cut at the budgets the
// loop proposes, each cut held to the host, and the least cost among the held kept.
#include "record_image.h"
#include "emit_vhdl.h"
#include "krep.h"

#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <algorithm>
#include <map>
#include <string>
#include <vector>

struct VhdlTally
{
    unsigned int checks;
    unsigned int failed;
    unsigned int not_held;
};

// where GHDL runs: the folder it analyzes into and runs in, and the bench's file; 1 where each lane is also
// synthesized; and 1 where a construction set was given, its forms' costs, and the dearest of them, which bounds the
// budgets the refinement loop proposes
struct VhdlPlace
{
    std::string work;
    std::string bench;
    int synthesis;
    int constructed;
    std::map<std::string, unsigned int> costs;
    unsigned int budget;
};

// the construction set at `path` into `place`: each form's cost by its name, and the largest; 0 where it is not read
// whole
static int vhdl_construction(const char *path, VhdlPlace *place)
{
    KrepFormTable table;
    EngineError error;
    memset(&error, 0, sizeof(error));
    if (krep_forms_read(path, &table, &error) == 0)
    {
        return 0;
    }
    std::string names;
    for (unsigned long long at = 0ull; at < (8ull * table.name_words); at += 1ull)
    {
        names.push_back((char)((table.words[table.forms + (at / 8ull)] >> (8ull * (at % 8ull))) & 0xFFull));
    }
    size_t start = 0u;
    for (unsigned long long form = 0ull; form < table.forms; form += 1ull)
    {
        const size_t end = names.find('\0', start);
        // a form's cost is a path's length in cells, far under 2^32
        const unsigned int cost = (unsigned int)table.words[form];
        place->costs[names.substr(start, end - start)] = cost;
        place->budget = (cost > place->budget) ? cost : place->budget;
        start = end + 1u;
    }
    krep_forms_release(&table);
    place->constructed = 1;
    return 1;
}

// the memory a lane is synthesized over, in words: synthesis reads no image, and a small memory keeps the netlist small
#define VHDL_TEST_SYNTHESIS_WORDS 256u

static void vhdl_check(VhdlTally *tally, int held, const std::string &what)
{
    tally->checks += 1u;
    tally->failed += held ? 0u : 1u;
    printf("  %s %s\n", held ? "ok  " : "FAIL", what.c_str());
}

static int vhdl_write(const std::string &path, const std::string &text)
{
    FILE *const file = fopen(path.c_str(), "wb");
    if (file == NULL)
    {
        return 0;
    }
    const int written = fwrite(text.data(), 1u, text.size(), file) == text.size();
    return (fclose(file) == 0) && written;
}

// the number after `label` on the first line of `path` that holds it; 0 where none does
static unsigned long long vhdl_after(const std::string &path, const char *label)
{
    FILE *const file = fopen(path.c_str(), "rb");
    if (file == NULL)
    {
        return 0ull;
    }
    char line[1024];
    unsigned long long found = 0ull;
    while ((found == 0ull) && (fgets(line, sizeof(line), file) != NULL))
    {
        const char *const at = strstr(line, label);
        found = (at != NULL) ? strtoull(at + strlen(label), NULL, 10) : 0ull;
    }
    fclose(file);
    return found;
}

// the lines of `path` that hold `label`
static unsigned long long vhdl_lines(const std::string &path, const char *label)
{
    FILE *const file = fopen(path.c_str(), "rb");
    if (file == NULL)
    {
        return 0ull;
    }
    char line[1024];
    unsigned long long found = 0ull;
    while (fgets(line, sizeof(line), file) != NULL)
    {
        found += (strstr(line, label) != NULL) ? 1ull : 0ull;
    }
    fclose(file);
    return found;
}

// what one cut of a lane gave: GHDL's run (read 1 where its records were read whole, the lanes refused, the records'
// words and the clocks the lanes ran), and where it was synthesized (synthesized 1 where GHDL and Yosys both ran), the
// memories Yosys inferred, the read ports it registered, its cells and its longest path between registers in cells.
// Its cost is the clocks times the longest path, the lanes' run in cells of delay, or the clocks where it was not
// synthesized
struct VhdlTrial
{
    int read;
    unsigned int refused;
    std::vector<unsigned int> records;
    unsigned long long clocks;
    int synthesized;
    unsigned long long memories;
    unsigned long long registered;
    unsigned long long cells;
    unsigned long long path;
    unsigned long long cost;
};

// the program in the work folder's program.vhd, its resident and its lane, synthesized into `trial` from the resident
// down: GHDL's synthesis as Verilog, then Yosys's generic synthesis. The memories Yosys inferred are its $mem_v2 cells
// where its synthesis stops before the fine stage, since the generic fine stage maps each memory to flops; a read port
// is registered where Yosys took the flops its word lands in into the port, as a block RAM's read is
static void vhdl_synthesize(const VhdlPlace *place, VhdlTrial *trial)
{
    const std::string command =
        "cd '" + place->work + "' && ghdl --synth --std=08 -gwords=" + std::to_string(VHDL_TEST_SYNTHESIS_WORDS)
        + " --out=verilog program.vhd -e cycle_program_unit > synth.v 2> synth.log && yosys -p \"read_verilog synth.v; "
          "synth -top cycle_program_unit -run :fine; tee -q -o memories.log stat; "
          "synth -top cycle_program_unit -run fine:; stat; ltp -noff\" > yosys.log 2>&1";
    const int status = system(command.c_str());
    trial->memories = vhdl_after(place->work + "/memories.log", "$mem_v2");
    trial->registered = vhdl_lines(place->work + "/yosys.log", "merging output FF");
    trial->cells = vhdl_after(place->work + "/yosys.log", "Number of cells:");
    trial->path = vhdl_after(place->work + "/yosys.log", "(length=");
    trial->synthesized = (status == 0) && (trial->cells != 0ull);
}

// `text` written as the work folder's program.vhd, run by GHDL under the bench over `image`, and where the place asks,
// synthesized
static void vhdl_try(const VhdlPlace *place, const std::string &text, const RecordImage *image, VhdlTrial *trial)
{
    *trial = VhdlTrial{0, 0u, {}, 0ull, 0, 0ull, 0ull, 0ull, 0ull, 0ull};
    const std::string records_path = place->work + "/records.txt";
    remove(records_path.c_str());
    const int written = !text.empty() && vhdl_write(place->work + "/program.vhd", text)
                     && record_image_write(place->work + "/memory.txt", image);
    const std::string command = "cd '" + place->work + "' && ghdl -a --std=08 program.vhd '" + place->bench
                              + "' > ghdl.log 2>&1 && ghdl --elab-run --std=08 record_vhdl_bench -gwords="
                              + std::to_string(image->memory.size()) + " >> ghdl.log 2>&1";
    const int status = written ? system(command.c_str()) : -1;
    trial->read = (status == 0) && record_image_read(records_path, image, &trial->refused, trial->records,
                                                     &trial->clocks);
    if (trial->read == 0)
    {
        printf("  GHDL did not run the lane (status %d); its log begins:\n", status);
        const std::string show = "head -20 '" + place->work + "/ghdl.log'";
        fflush(stdout);
        (void)system(show.c_str());
    }
    if (place->synthesis && trial->read)
    {
        vhdl_synthesize(place, trial);
    }
    trial->cost = trial->clocks * (trial->synthesized ? trial->path : 1ull);
}

// the lines and checks of one cut: its run held to the host's (a refusal where the host refuses the run), and where
// it was synthesized, what synthesis gave. Returns 1 where its run is the host's
static int vhdl_report(VhdlTally *tally, const VhdlPlace *place, const std::string &what, const VhdlTrial *trial,
                       int refuses, int host_ran, const std::vector<unsigned int> &host_records)
{
    const int held = refuses ? (trial->read && !host_ran && (trial->refused != 0u))
                             : (trial->read && host_ran && (trial->refused == 0u) && (trial->records == host_records));
    vhdl_check(tally, held,
               what + (refuses ? " as VHDL refuses a lane where the host refuses the run"
                               : " as VHDL writes the host's records word for word"));
    if (place->synthesis && trial->read)
    {
        printf("  %s, synthesized over %u words: %llu memories inferred, %llu read ports registered, %llu cells, the "
               "longest path %llu cells; %llu clocks, cost %llu\n",
               what.c_str(), VHDL_TEST_SYNTHESIS_WORDS, trial->memories, trial->registered, trial->cells, trial->path,
               trial->clocks, trial->cost);
        vhdl_check(tally, trial->synthesized, what + " is synthesized by GHDL and Yosys");
    }
    return held;
}

// what each run of a program is given: the tally and the place
struct VhdlRun
{
    VhdlTally *tally;
    const VhdlPlace *place;
};

// the program laid, run on the host, written as VHDL and run by GHDL over the same atoms; its line printed and its
// check made. `refuses` is 1 for a program the host must refuse: the lane as VHDL must then refuse a lane
static void vhdl_run(void *context, const HostProgram *program, int reuse, unsigned int *const *atoms,
                     const unsigned long long *bodies, const unsigned int *index, int refuses)
{
    VhdlTally *const tally = ((VhdlRun *)context)->tally;
    const VhdlPlace *const place = ((VhdlRun *)context)->place;
    const std::string name = std::string(program->name) + (reuse ? " (registers reused)" : "");
    HostLoaded loaded;
    if (host_load(program, reuse, &loaded) == 0)
    {
        vhdl_check(tally, 0, name + " is laid");
        return;
    }
    const EngineRecordLayout *const layout = &loaded.layout;
    const unsigned long long record_words = (unsigned long long)HOST_TEST_LANES * layout->out_limbs;
    std::vector<unsigned int> host_records((size_t)record_words, 0u);
    CycleRecordHostRequest request;
    memset(&request, 0, sizeof(request));
    request.layout = layout;
    for (unsigned int member = 0u; member < layout->members; member += 1u)
    {
        request.in[member] = atoms[member];
        request.bodies[member] = bodies[member];
    }
    request.index = index;
    request.count = HOST_TEST_LANES;
    request.out = host_records.data();
    request.error = &loaded.error;
    const long ran = cycle_record_run_host(&request);
    unsigned long long inputs = HOST_TEST_FNV_BASIS;
    for (unsigned int member = 0u; member < layout->members; member += 1u)
    {
        inputs ^= host_digest(atoms[member], bodies[member] * layout->in_limbs[member]);
    }
    EmitVhdl &emit = emit_vhdl();
    const EmitTarget target = {0ull, 0, 0, 0, 0, ""};
    unsigned int places = 0u;
    unsigned int live = 0u;
    const std::string text =
        (emit.ruleset(1) != NULL) ? emit.program(layout, &target, std::string(), &places, &live) : std::string();
    if (text.empty())
    {
        printf("  %s: %u steps, not held in VHDL (a step the lane does not hold, or its ruleset refused)\n",
               name.c_str(), layout->steps);
        tally->not_held += 1u;
        host_free(&loaded);
        return;
    }
    const RecordImage image = record_image(layout, atoms, bodies, index);
    const int host_ran = ran == (long)HOST_TEST_LANES;
    const unsigned long long host_records_digest = host_ran ? host_digest(host_records.data(), record_words) : 0ull;

    // the lane cut at the two ends of what a construction set can ask: only where the lane must be cut, and every form
    // alone in a state of its own
    const EmitLaneShape ends[2] = {{{}, 0u, EMIT_LANE_UNBOUNDED, EMIT_LANE_UNBOUNDED},
                                    {{}, 1u, 1u, EMIT_LANE_UNBOUNDED}};
    const char *const end_names[2] = {"cut where it must be", "every form alone"};
    unsigned long long end_costs[2] = {0ull, 0ull};
    for (unsigned int end = 0u; end < 2u; end += 1u)
    {
        EmitLaneShaped shaped = {0u, 0u, 0u};
        const std::string cut = emit.shaped(layout, &target, std::string(), &places, &live, ends[end], &shaped);
        const std::string what = name + ", " + end_names[end];
        if (end == 0u)
        {
            vhdl_check(tally, cut == text, name + ": program() is the lane cut where it must be");
        }
        VhdlTrial trial;
        vhdl_try(place, cut, &image, &trial);
        printf("  %s: %u steps, %u out limbs, %zu lines of VHDL, %u states, inputs %016llx, records %016llx as VHDL, "
               "%016llx on the host, %u lanes refused as VHDL\n",
               what.c_str(), layout->steps, layout->out_limbs, (size_t)std::count(cut.begin(), cut.end(), '\n'),
               shaped.states, inputs, trial.read ? host_digest(trial.records.data(), record_words) : 0ull,
               host_records_digest, trial.refused);
        end_costs[end] = vhdl_report(tally, place, what, &trial, refuses, host_ran, host_records) ? trial.cost : 0ull;
    }

    // the refinement loop (engine_table M23), where a construction set was given: the generator is the cut, its knob
    // the budget a state is cut at, proposed from 1 and doubled until it passes twice the dearest form; the critic is
    // GHDL's run held to the host on every lane and the cost measured. A budget whose lane is the text of one tried
    // before is not tried again. A round is kept only where its lanes are the host's, and the best is the least cost
    // among the kept
    if (place->constructed == 0)
    {
        host_free(&loaded);
        return;
    }
    std::vector<std::string> tried;
    unsigned long long best_cost = 0ull;
    unsigned int best_budget = 0u;
    unsigned int rounds = 0u;
    for (unsigned int budget = 1u; budget <= (4u * place->budget); budget *= 2u)
    {
        const EmitLaneShape shape = {place->costs, 0u, budget, EMIT_LANE_UNBOUNDED};
        EmitLaneShaped shaped = {0u, 0u, 0u};
        const std::string cut = emit.shaped(layout, &target, std::string(), &places, &live, shape, &shaped);
        if (std::find(tried.begin(), tried.end(), cut) != tried.end())
        {
            continue;
        }
        tried.push_back(cut);
        rounds += 1u;
        const std::string what = name + ", round " + std::to_string(rounds) + " at budget " + std::to_string(budget);
        VhdlTrial trial;
        vhdl_try(place, cut, &image, &trial);
        printf("  %s: %u states (the most cost one chains %u, %u forms alone past the budget), records %016llx as "
               "VHDL\n",
               what.c_str(), shaped.states, shaped.most, shaped.over,
               trial.read ? host_digest(trial.records.data(), record_words) : 0ull);
        const int kept = vhdl_report(tally, place, what, &trial, refuses, host_ran, host_records);
        if (kept && ((best_budget == 0u) || (trial.cost < best_cost)))
        {
            best_cost = trial.cost;
            best_budget = budget;
        }
    }
    printf("  %s: the refinement loop kept budget %u at cost %llu over %u rounds; cut where it must be costs %llu, "
           "every form alone %llu\n",
           name.c_str(), best_budget, best_cost, rounds, end_costs[0], end_costs[1]);
    host_free(&loaded);
}

int main(int argc, char **argv)
{
    VhdlPlace place = {std::string(), std::string(), 0, 0, {}, 0u};
    int usable = argc >= 3;
    for (int at = 3; usable && (at < argc); at += 1)
    {
        const int construction = (strcmp(argv[at], "--construction") == 0) && ((at + 1) < argc);
        place.synthesis = place.synthesis || (strcmp(argv[at], "--synthesis") == 0);
        usable = construction ? vhdl_construction(argv[at + 1], &place) : (strcmp(argv[at], "--synthesis") == 0);
        at += construction ? 1 : 0;
    }
    if (!usable)
    {
        fprintf(stderr, "usage: record_vhdl_test <work folder> <record_vhdl_bench.vhd> [--synthesis] "
                        "[--construction <vhdl.kcs>], the construction set read whole\n");
        return 2;
    }
    place.work = argv[1];
    place.bench = argv[2];
    VhdlTally tally = {0u, 0u, 0u};
    printf("  record vhdl test: %u lanes a program, ANCHOR_EXACT_LIMBS %u, %s\n", HOST_TEST_LANES,
           (unsigned int)ANCHOR_EXACT_LIMBS,
           place.constructed ? ("a construction set of " + std::to_string(place.costs.size()) + " forms").c_str()
                             : "no construction set");
    VhdlRun run = {&tally, &place};
    record_image_programs(&run, vhdl_run);
    printf("  record vhdl test: %u checks, %u failed, %u programs not held in VHDL\n", tally.checks, tally.failed,
           tally.not_held);
    return (tally.failed == 0u) ? 0 : 1;
}
