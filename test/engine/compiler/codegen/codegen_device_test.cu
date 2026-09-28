// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// The compiler on the device checked against the compiler on the host (engine_table.md item 11(f)(a)).
// record_host_test's programs, drawn from the same stream in the same order (record_image.h), are laid out on the host
// by keymath and key_schedule and on the device by the same cores (keymath_core.h, key_schedule_core.h, layout_device):
// the two layouts must agree word for word. In each language of the register lane, PTX, C and VHDL, the forms the
// device decides (codegen_device_instrs) must be the host's (CodeGenerator::decided) item for item, as the lane runs
// and split into states by a schedule model, with the schedule's states, most chained cost and forms over the budget
// the host's. The text the device writes from the host's layout (codegen_device) and from its own
// (codegen_device_steps) must be the code generator's byte for byte, where the assembly printer takes the language's
// ruleset. Last, the bootstrap's fixed point: the assembly printer's own lane, written by the device with the assembly
// printer, must be the code generator's. The test is one job on the device's tessera daemon, submitted before its first
// device work.
#include "../cycle/record_image.h"
#include "c_target.h"
#include "codegen_device.h"
#include "ptx_target.h"
#include "ruleset_reader.h"
#include "sim.h"
#include "vhdl_target.h"

#include <cuda_runtime.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <string>
#include <vector>

// the most the test puts on the device at once: a lane's forms, records and bytes, and the assembly printer, each a
// few megabytes at most for these programs. The first run peaked 8 MB over its process's CUDA context
#define DEVICE_TEST_DECLARED (64ull << 20u)

// the schedule model each lane is split by: every form a cost of 1, four to a state, one write a state
#define DEVICE_TEST_BUDGET 4u

#define DEVICE_TEST_LANGUAGES 3u

// the header each lane is written under, which the assembly printer takes whole
static const char s_device_header[] = "// codegen_device_test\n";

// the checks made and failed, and the lanes a language does not hold
struct DeviceResults
{
    unsigned int checks;
    unsigned int failed;
    unsigned int unsupported;
};

static void device_check(DeviceResults *results, int passed, const std::string &what)
{
    results->checks += 1u;
    results->failed += passed ? 0u : 1u;
    printf("  %s %s\n", passed ? "ok  " : "FAIL", what.c_str());
}

// 1 where two lists of forms are the same item for item
static int device_items_same(const std::vector<MachineInstr> &left, const std::vector<MachineInstr> &right)
{
    return (left.size() == right.size()) &&
           ((left.empty()) || (memcmp(left.data(), right.data(), left.size() * sizeof(MachineInstr)) == 0));
}

// what the device gave, or why it did not
static std::string device_why(int ok, const std::string &refused)
{
    return ok ? std::string() : (" (" + refused + ")");
}

static std::string device_text_differ(const std::string &host, const std::string &device);

// one language's lane of a program: its forms as the lane runs and split, and its text, the device's checked against
// the host's
static void device_language(DeviceResults *results, const std::string &name, CodeGenerator *generator,
                            const char *language, const EngineRecordLayout *layout, const LayoutRequest *request)
{
    const std::string lane = name + " in " + language;
    const Ruleset *const rules = generator->ruleset(1);
    if (rules == NULL)
    {
        device_check(results, 0, lane + ": the ruleset is read");
        return;
    }
    const unsigned int scratch_banks[3] = {REGCLASS_TEMPORARY, REGCLASS_WIDE, REGCLASS_PREDICATE};
    std::vector<unsigned int> scratch;
    ruleset_scratch(rules, scratch_banks, &scratch);
    std::vector<MachineInstr> host_items;
    std::vector<MachineInstr> device_items;
    unsigned int places = 0u;
    std::string refused;
    if (generator->decided(layout, &places, &host_items) == 0)
    {
        printf("  %s: %u steps, not supported (a step the lane does not support, or a form breaks the lane)\n",
               lane.c_str(), layout->steps);
        results->unsupported += 1u;
        return;
    }
    // the lane as program() writes it: whole, or split where the language always splits it
    ScheduleCosts program_costs;
    const ScheduleCosts *const written_costs =
        generator->program_schedule_costs(&program_costs) ? &program_costs : NULL;
    ScheduleReport written_report = {0u, 0u, 0u};
    const int decided =
        codegen_device_instrs(layout, scratch, places, written_costs, &written_report, &device_items, &refused);
    device_check(results, decided && device_items_same(host_items, device_items),
                 lane + ": the device decides the host's " + std::to_string(host_items.size()) + " forms" +
                     device_why(decided, refused));
    // the lane split into states
    ScheduleModel model;
    model.other = 1u;
    model.budget = DEVICE_TEST_BUDGET;
    model.writes = 1u;
    ScheduleReport host_report = {0u, 0u, 0u};
    ScheduleReport device_report = {0u, 0u, 0u};
    unsigned int scheduled_places = 0u;
    if (generator->decided(layout, model, &host_report, &scheduled_places, &host_items) != 0)
    {
        const ScheduleCosts costs = generator->schedule_costs(model);
        const int scheduled_decided =
            codegen_device_instrs(layout, scratch, scheduled_places, &costs, &device_report, &device_items, &refused);
        device_check(results,
                     scheduled_decided && device_items_same(host_items, device_items) &&
                         (device_report.states == host_report.states) &&
                         (device_report.maximum == host_report.maximum) && (device_report.over == host_report.over),
                     lane + " split into " + std::to_string(host_report.states) +
                         " states: the device splits it as the host does" + device_why(scheduled_decided, refused));
    }
    else
    {
        printf("  %s: the host does not split the lane by the test's schedule model\n", lane.c_str());
    }
    // the text, where the assembly printer takes the language's ruleset
    const TargetInfo target = {0ull, 0, 0, 0, 0, ""};
    unsigned int live = 0u;
    const std::string text = generator->program(layout, &target, std::string(s_device_header), &places, &live);
    AsmPrinterRuleset text_rules{};
    if (asm_printer_ruleset_build(rules, &target, std::string(s_device_header), &text_rules, &refused) == 0)
    {
        printf("  %s: the assembly printer does not take the ruleset (%s)\n", lane.c_str(), refused.c_str());
        return;
    }
    Ruleset device_read{};
    device_read.schema = rules->schema;
    std::string read_refused;
    const int read_ran = ruleset_read_device(&device_read, rules->path, &read_refused);
    device_check(results, read_ran && ruleset_same(&device_read, rules),
                 lane + ": the device reads the ruleset's file as the host does" + device_why(read_ran, read_refused));
    AsmPrinterRuleset device_rules{};
    std::string rules_refused;
    const int rules_built =
        asm_printer_ruleset_device(rules, &target, std::string(s_device_header), &device_rules, &rules_refused);
    device_check(results, rules_built && asm_printer_ruleset_same(&device_rules, &text_rules),
                 lane + ": the device builds the assembly printer's ruleset word for word the host's" +
                     device_why(rules_built, rules_refused));
    if (rules_built)
    {
        asm_printer_ruleset_release(&device_rules);
    }
    std::string written;
    const int wrote = codegen_device(layout, &text_rules, places, written_costs, &written, &refused);
    device_check(results, wrote && !text.empty() && (written == text),
                 lane + ": the device writes the code generator's " + std::to_string(text.size()) +
                     " bytes from the host's "
                     "layout" +
                     device_why(wrote, refused) + (wrote ? device_text_differ(text, written) : std::string()));
    std::string stepped;
    const int stepped_wrote = codegen_device_steps(request, &text_rules, places, written_costs, &stepped, &refused);
    device_check(results, stepped_wrote && !text.empty() && (stepped == text),
                 lane + ": the device writes them from its own layout" + device_why(stepped_wrote, refused) +
                     (stepped_wrote ? device_text_differ(text, stepped) : std::string()));
    asm_printer_ruleset_release(&text_rules);
}

// where the device's text first leaves the code generator's: the byte and a few lines of each from the line it is on
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
    return " (" + std::to_string(host.size()) + " bytes on the host, " + std::to_string(device.size()) +
           " from the device, first differing at byte " + std::to_string(at) +
           ")\n    host:   " + host.substr(from, 160u) + "\n    device: " + device.substr(from, 160u);
}

// the program laid out on the host and on the device, and each language's lane of it
static void device_run(void *context, const HostProgram *program, int reuse, unsigned int *const *atoms,
                       const unsigned long long *bodies, const unsigned int *index, int refuses)
{
    (void)atoms;
    (void)bodies;
    (void)index;
    (void)refuses;
    DeviceResults *const results = (DeviceResults *)context;
    const std::string name = std::string(program->name) + (reuse ? " (registers reused)" : "");
    HostLoaded loaded;
    if (host_load(program, reuse, &loaded) == 0)
    {
        device_check(results, 0, name + " is laid out on the host");
        return;
    }
    LayoutRequest request{};
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
    EngineRecordLayout device_layout{};
    std::string refused;
    const int device_built = layout_device(&request, &device_layout, &refused);
    device_check(results, device_built && layout_same(&device_layout, &loaded.layout),
                 name + ": the device lays out the host's " + std::to_string(loaded.layout.steps) + " steps and " +
                     std::to_string(loaded.layout.file_limbs) + " limbs of file word for word" +
                     device_why(device_built, refused));
    if (device_built)
    {
        key_schedule_record_release(&device_layout);
    }
    CodeGenerator *const generators[DEVICE_TEST_LANGUAGES] = {&ptx_target(), &c_target(), &vhdl_target()};
    const char *const languages[DEVICE_TEST_LANGUAGES] = {"PTX", "C", "VHDL"};
    for (unsigned int language = 0u; language < DEVICE_TEST_LANGUAGES; language += 1u)
    {
        device_language(results, name, generators[language], languages[language], &loaded.layout, &request);
    }
    host_free(&loaded);
}

// The bootstrap's fixed point: the assembly printer's own lane in a language, written by the device with the text
// program from the step table the device laid out, must be the code generator's text byte for byte: the assembly
// printer writes itself
static void device_bootstrap(DeviceResults *results, CodeGenerator *generator, const char *language)
{
    const std::string lane = std::string("the assembly printer's own lane in ") + language;
    const Ruleset *const rules = generator->ruleset(1);
    const TargetInfo target = {0ull, 0, 0, 0, 0, ""};
    AsmPrinterRuleset text_rules{};
    std::string refused;
    if ((rules == NULL) ||
        (asm_printer_ruleset_build(rules, &target, std::string(s_device_header), &text_rules, &refused) == 0))
    {
        printf("  %s: the assembly printer does not take the ruleset (%s)\n", lane.c_str(),
               (rules == NULL) ? "it is not read" : refused.c_str());
        return;
    }
    const AsmPrinterProgram &program = text_rules.program;
    const unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX] = {ASM_PRINTER_RECORD_LIMBS, 0u, 0u};
    LayoutRequest request{};
    request.steps = program.steps.data();
    // the assembly printer's steps are a few hundred, and its fields and tables a handful
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
    const std::string text = generator->program(&program.layout, &target, std::string(s_device_header), &places, &live);
    std::string written;
    ScheduleCosts program_costs;
    const ScheduleCosts *const written_costs =
        generator->program_schedule_costs(&program_costs) ? &program_costs : NULL;
    const int wrote = codegen_device_steps(&request, &text_rules, places, written_costs, &written, &refused);
    device_check(results, wrote && !text.empty() && (written == text),
                 lane + ", " + std::to_string(program.layout.steps) +
                     " steps: the device writes it with the text "
                     "program, the code generator's " +
                     std::to_string(text.size()) + " bytes" + device_why(wrote, refused) +
                     (wrote ? device_text_differ(text, written) : std::string()));
    asm_printer_ruleset_release(&text_rules);
}

int main(int count, char **arguments)
{
    DeviceResults results = {0u, 0u, 0u};
    char job_capacity[SIM_LINE_CAPACITY];
    SimResults job;
    sim_open(&job, job_capacity);
    const int admitted = sim_job_submit(&job, "codegen_device_test", count, arguments, DEVICE_TEST_DECLARED);
    if (admitted != 0)
    {
        record_image_programs(&results, device_run);
        device_bootstrap(&results, &ptx_target(), "PTX");
        device_bootstrap(&results, &c_target(), "C");
        device_bootstrap(&results, &vhdl_target(), "VHDL");
    }
    sim_job_release(&job);
    sim_flush(&job);
    device_check(&results, (admitted != 0) && (job.failures == 0ull),
                 "tessera: the device's daemon admits the test's job and it releases");
    printf("  codegen device test: %u checks, %u failed, %u lanes not supported\n", results.checks, results.failed,
           results.unsupported);
    return (results.failed == 0u) ? 0 : 1;
}
