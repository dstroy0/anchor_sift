// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// The compiler on the device held to the compiler on the host (engine_table.md item 11(f)(a)). record_host_test's
// programs, drawn from the same stream in the same order (record_image.h), are laid on the host by keymath and
// key_schedule and on the device by the same cores (keymath_core.h, key_schedule_core.h, emit_lay_device): the two
// layouts must agree word for word. In each language of the register lane, PTX, C and VHDL, the forms the device
// decides (emit_device_items) must be the host's (EmitLane::decided) item for item, as the lane runs and cut
// into states by a shape, with the cut's states, most chained cost and forms over the budget the host's. The text the
// device writes from the host's layout (emit_device) and from its own (emit_device_steps) must be the
// emitter's byte for byte, where the text program takes the language's ruleset. Last, the bootstrap's fixed point: the
// text program's own lane, written by the device with the text program, must be the emitter's. The test is one
// job on the device's tessera daemon, submitted before its first device work.
#include "record_image.h"
#include "emit_device.h"
#include "emit_ptx.h"
#include "emit_rules.h"
#include "emit_source.h"
#include "emit_vhdl.h"
#include "sim.h"

#include <cuda_runtime.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <string>
#include <vector>

// the most the test puts on the device at once: a lane's forms, records and bytes, and the text program, each a
// few megabytes at most for these programs. The first run peaked 8 MB over its process's CUDA context
#define DEVICE_TEST_DECLARED (64ull << 20u)

// the shape each lane is cut by: every form a cost of 1, four to a state, one write a state
#define DEVICE_TEST_BUDGET 4u

#define DEVICE_TEST_LANGUAGES 3u

// the header each lane is written under, which the text program takes whole
static const char s_device_header[] = "// emit_device_test\n";

// the checks made and failed, and the lanes a language does not hold
struct DeviceTally
{
    unsigned int checks;
    unsigned int failed;
    unsigned int not_held;
};

static void device_check(DeviceTally *tally, int held, const std::string &what)
{
    tally->checks += 1u;
    tally->failed += held ? 0u : 1u;
    printf("  %s %s\n", held ? "ok  " : "FAIL", what.c_str());
}

// 1 where two lists of forms are the same item for item
static int device_items_same(const std::vector<EmitCoreItem> &left, const std::vector<EmitCoreItem> &right)
{
    return (left.size() == right.size())
        && ((left.empty()) || (memcmp(left.data(), right.data(), left.size() * sizeof(EmitCoreItem)) == 0));
}

// what the device gave, or why it did not
static std::string device_why(int held, const std::string &refused)
{
    return held ? std::string() : (" (" + refused + ")");
}

static std::string device_text_differ(const std::string &host, const std::string &device);

// one language's lane of a program: its forms as the lane runs and cut, and its text, the device's held to the host's
static void device_language(DeviceTally *tally, const std::string &name, EmitLane *emit, const char *language,
                            const EngineRecordLayout *layout, const EmitLayRequest *request)
{
    const std::string lane = name + " in " + language;
    const EmitRuleset *const rules = emit->ruleset(1);
    if (rules == NULL)
    {
        device_check(tally, 0, lane + ": the ruleset is read");
        return;
    }
    const unsigned int scratch_banks[3] = {EMIT_BANK_TEMPORARY, EMIT_BANK_WIDE, EMIT_BANK_PREDICATE};
    std::vector<unsigned int> scratch;
    emit_ruleset_scratch(rules, scratch_banks, &scratch);
    std::vector<EmitCoreItem> host_items;
    std::vector<EmitCoreItem> device_items;
    unsigned int places = 0u;
    std::string refused;
    if (emit->decided(layout, &places, &host_items) == 0)
    {
        printf("  %s: %u steps, not held (a step the lane does not hold, or a form breaks the lane)\n", lane.c_str(),
               layout->steps);
        tally->not_held += 1u;
        return;
    }
    // the lane as program() writes it: whole, or cut where the language always cuts it
    EmitLaneCut program_cut;
    const EmitLaneCut *const written_cut = emit->program_cut(&program_cut) ? &program_cut : NULL;
    EmitLaneShaped written_report = {0u, 0u, 0u};
    const int decided =
        emit_device_items(layout, scratch, places, written_cut, &written_report, &device_items, &refused);
    device_check(tally, decided && device_items_same(host_items, device_items),
                 lane + ": the device decides the host's " + std::to_string(host_items.size()) + " forms"
                     + device_why(decided, refused));
    // the lane cut into states
    EmitLaneShape shape;
    shape.other = 1u;
    shape.budget = DEVICE_TEST_BUDGET;
    shape.writes = 1u;
    EmitLaneShaped host_report = {0u, 0u, 0u};
    EmitLaneShaped device_report = {0u, 0u, 0u};
    unsigned int cut_places = 0u;
    if (emit->decided(layout, shape, &host_report, &cut_places, &host_items) != 0)
    {
        const EmitLaneCut cut = emit->cut(shape);
        const int cut_decided =
            emit_device_items(layout, scratch, cut_places, &cut, &device_report, &device_items, &refused);
        device_check(tally,
                     cut_decided && device_items_same(host_items, device_items)
                         && (device_report.states == host_report.states) && (device_report.most == host_report.most)
                         && (device_report.over == host_report.over),
                     lane + " cut into " + std::to_string(host_report.states)
                         + " states: the device cuts it as the host does" + device_why(cut_decided, refused));
    }
    else
    {
        printf("  %s: the host does not cut the lane by the test's shape\n", lane.c_str());
    }
    // the text, where the text program takes the language's ruleset
    const EmitTarget target = {0ull, 0, 0, 0, 0, ""};
    unsigned int live = 0u;
    const std::string text = emit->program(layout, &target, std::string(s_device_header), &places, &live);
    EmitTextRuleset text_rules{};
    if (emit_text_ruleset_lay(rules, &target, std::string(s_device_header), &text_rules, &refused) == 0)
    {
        printf("  %s: the text program does not take the ruleset (%s)\n", lane.c_str(), refused.c_str());
        return;
    }
    std::string written;
    const int wrote = emit_device(layout, &text_rules, places, written_cut, &written, &refused);
    device_check(tally, wrote && !text.empty() && (written == text),
                 lane + ": the device writes the emitter's " + std::to_string(text.size()) + " bytes from the host's "
                     "layout" + device_why(wrote, refused)
                     + (wrote ? device_text_differ(text, written) : std::string()));
    std::string stepped;
    const int stepped_wrote = emit_device_steps(request, &text_rules, places, written_cut, &stepped, &refused);
    device_check(tally, stepped_wrote && !text.empty() && (stepped == text),
                 lane + ": the device writes them from its own layout" + device_why(stepped_wrote, refused)
                     + (stepped_wrote ? device_text_differ(text, stepped) : std::string()));
    emit_text_ruleset_release(&text_rules);
}

// where the device's text first leaves the emitter's: the byte and a few lines of each from the line it is on
static std::string device_text_differ(const std::string &host, const std::string &device)
{
    if (host == device)
    {
        return std::string();
    }
    size_t at = 0u;
    while ((at < host.size()) && (at < device.size()) && (host[at] == device[at]))
    {
        at += 1u;
    }
    const size_t line = host.rfind('\n', (at == 0u) ? 0u : (at - 1u));
    const size_t from = ((line == std::string::npos) || (at == 0u)) ? 0u : (line + 1u);
    return " (" + std::to_string(host.size()) + " bytes on the host, " + std::to_string(device.size())
         + " from the device, first differing at byte " + std::to_string(at) + ")\n    host:   "
         + host.substr(from, 160u) + "\n    device: " + device.substr(from, 160u);
}

// the program laid on the host and on the device, and each language's lane of it
static void device_run(void *context, const HostProgram *program, int reuse, unsigned int *const *atoms,
                       const unsigned long long *bodies, const unsigned int *index, int refuses)
{
    (void)atoms;
    (void)bodies;
    (void)index;
    (void)refuses;
    DeviceTally *const tally = (DeviceTally *)context;
    const std::string name = std::string(program->name) + (reuse ? " (registers reused)" : "");
    HostLoaded loaded;
    if (host_load(program, reuse, &loaded) == 0)
    {
        device_check(tally, 0, name + " is laid on the host");
        return;
    }
    EmitLayRequest request{};
    request.steps = program->steps;
    request.count = program->count;
    request.field_bits = program->field_bits;
    request.field_offset = program->field_offset;
    request.fields = program->fields;
    request.members = program->members;
    request.in_limbs = program->in_limbs;
    request.outputs = program->outputs;
    request.output_count = program->output_count;
    request.tables = (program->table_count != 0u) ? program->tables : NULL;
    request.table_count = program->table_count;
    request.reuse = reuse;
    EngineRecordLayout laid{};
    std::string refused;
    const int device_laid = emit_lay_device(&request, &laid, &refused);
    device_check(tally, device_laid && emit_lay_same(&laid, &loaded.layout),
                 name + ": the device lays the host's " + std::to_string(loaded.layout.steps) + " steps and "
                     + std::to_string(loaded.layout.file_limbs) + " limbs of file word for word"
                     + device_why(device_laid, refused));
    if (device_laid)
    {
        key_schedule_record_release(&laid);
    }
    EmitLane *const emits[DEVICE_TEST_LANGUAGES] = {&emit_ptx(), &emit_source(), &emit_vhdl()};
    const char *const languages[DEVICE_TEST_LANGUAGES] = {"PTX", "C", "VHDL"};
    for (unsigned int language = 0u; language < DEVICE_TEST_LANGUAGES; language += 1u)
    {
        device_language(tally, name, emits[language], languages[language], &loaded.layout, &request);
    }
    host_free(&loaded);
}

// The bootstrap's fixed point: the text program's own lane in a language, written by the device with the text
// program from the step table the device laid, must be the emitter's text byte for byte: the text program writes
// itself
static void device_bootstrap(DeviceTally *tally, EmitLane *emit, const char *language)
{
    const std::string lane = std::string("the text program's own lane in ") + language;
    const EmitRuleset *const rules = emit->ruleset(1);
    const EmitTarget target = {0ull, 0, 0, 0, 0, ""};
    EmitTextRuleset text_rules{};
    std::string refused;
    if ((rules == NULL)
        || (emit_text_ruleset_lay(rules, &target, std::string(s_device_header), &text_rules, &refused) == 0))
    {
        printf("  %s: the text program does not take the ruleset (%s)\n", lane.c_str(),
               (rules == NULL) ? "it is not read" : refused.c_str());
        return;
    }
    const EmitTextProgram &program = text_rules.program;
    const unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX] = {EMIT_TEXT_RECORD_LIMBS, 0u, 0u};
    EmitLayRequest request{};
    request.steps = program.steps.data();
    // the text program's steps are a few hundred, and its fields and tables a handful
    request.count = (unsigned int)program.steps.size();
    request.field_bits = program.field_bits.data();
    request.field_offset = program.field_offset.data();
    request.fields = (unsigned int)program.field_bits.size();
    request.members = 1u;
    request.in_limbs = in_limbs;
    request.outputs = &program.output;
    request.output_count = 1u;
    request.tables = program.tables.data();
    request.table_count = (unsigned int)program.tables.size();
    request.reuse = 1;
    unsigned int places = 0u;
    unsigned int live = 0u;
    const std::string text = emit->program(&program.layout, &target, std::string(s_device_header), &places, &live);
    std::string written;
    EmitLaneCut program_cut;
    const EmitLaneCut *const written_cut = emit->program_cut(&program_cut) ? &program_cut : NULL;
    const int wrote = emit_device_steps(&request, &text_rules, places, written_cut, &written, &refused);
    device_check(tally, wrote && !text.empty() && (written == text),
                 lane + ", " + std::to_string(program.layout.steps) + " steps: the device writes it with the text "
                     "program, the emitter's " + std::to_string(text.size()) + " bytes" + device_why(wrote, refused)
                     + (wrote ? device_text_differ(text, written) : std::string()));
    emit_text_ruleset_release(&text_rules);
}

int main(int count, char **arguments)
{
    DeviceTally tally = {0u, 0u, 0u};
    char job_room[SIM_LINE_ROOM];
    SimTally job;
    sim_open(&job, job_room);
    const int admitted = sim_job_submit(&job, "emit_device_test", count, arguments, DEVICE_TEST_DECLARED);
    if (admitted != 0)
    {
        record_image_programs(&tally, device_run);
        device_bootstrap(&tally, &emit_ptx(), "PTX");
        device_bootstrap(&tally, &emit_source(), "C");
        device_bootstrap(&tally, &emit_vhdl(), "VHDL");
    }
    sim_job_release(&job);
    sim_flush(&job);
    device_check(&tally, (admitted != 0) && (job.failures == 0ull),
                 "tessera: the device's daemon admits the test's job and it releases");
    printf("  emit device test: %u checks, %u failed, %u lanes not held\n", tally.checks, tally.failed,
           tally.not_held);
    return (tally.failed == 0u) ? 0 : 1;
}
