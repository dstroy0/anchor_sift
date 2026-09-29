// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "code_generator.h"
#include "codegen_core.h"
#include "ruleset_reader.h"

#include <stddef.h>
#include <stdio.h>

#include <deque>
#include <initializer_list>
#include <map>
#include <mutex>
#include <string>
#include <vector>

static const RulesetName s_opcode_names[OPCODE_COUNT] = {OPCODES(OPCODE_WRITTEN)};

static const RulesetName s_regclass_names[REGCLASS_COUNT] = {REGCLASSES(REGCLASS_WRITTEN)};

static const RulesetName s_physreg_names[PHYSREG_COUNT] = {PHYSREGS(PHYSREG_WRITTEN)};

// The record program as a register lane, in any language whose ruleset writes the lane's forms (PTX's is
// ptx.krs): each step unrolled at its widths into straight-line text over registers the lane holds itself. The
// file is a bank by place and its signs another, as key_schedule laid them out; the record's words are a bank, laid out
// by each put and each stored once the last put that lays it out has run; the atoms' words are a bank, each loaded
// at its first reader. What a compiler would loop over a register's limbs is written out here limb by limb from
// the program's own widths. The code generator writes no text of its own: every line is a form of the language's
// ruleset, and every register a written form of its banks and fixed registers. The code generator decides what a step
// does and the ruleset how the language writes it. What each step does, and the lane's opening, close and split into
// states, is decided in codegen_core.h, which the device compiles as well; here the forms it decides are written in the
// ruleset and laid out into the text in its order. The steps that loop on their values are loops of the same forms,
// each body over registers of fixed widths so no limb is named by a value the lane computes: the gcd, the golden
// ladder, a division by more than one limb, and a product too wide to unroll. A loop is a label and a branch back to it
// on a predicate, which a language that clocks the lane splits into states that go back. The lane calls nothing and
// takes no shared memory. Every step is the interpreter's arithmetic limb for limb, branch-free where the interpreter
// branches on a sign or a borrow, and CYCLE_RECORD_CHECK=1 holds the two to each other. After the lane comes the
// program resident that runs its launch's lanes (program_unit), the kernel the record machine launches or a circuit's
// top. The text is the whole program, and nothing hand-written is linked with it.

// Where each bank begins in the register file, and how many registers one of its own takes. A language whose
// registers are virtual (PTX's %v and %t, C's arrays, VHDL's variables) gives every bank a namespace of its own and
// leaves this zero; a language with one register file (SASS) has every bank in that file, and a bank numbered from 0
// like every other collides with them. The banks are laid end to end from the counts the lane declares, and a bank
// whose registers are 64 bits takes two of the file's for each of its own.
struct RegisterFile
{
    unsigned int at[REGCLASS_COUNT];
    unsigned int takes[REGCLASS_COUNT];
};

// register `at` of a bank, as the ruleset writes it, laid into the file by `file` where the language has one
static std::string code_generator_register(const Ruleset *rules, const RegisterFile *file, unsigned int bank,
                                           unsigned int at)
{
    const InstrTemplate *const form = &rules->banks[bank];
    const std::string number = std::to_string(file->at[bank] + (file->takes[bank] * at));
    std::string name = form->pieces[0];
    for (size_t slot = 0u; slot < form->slots.size(); slot += 1u)
    {
        name += number;
        name += form->pieces[slot + 1u];
    }
    return name;
}

// an argument the core decided, as the ruleset writes it: a register by its bank, a fixed register by its name, and a
// number in decimal, a signed one with its minus
static std::string code_generator_argument(const Ruleset *rules, const RegisterFile *file,
                                           const MachineOperand &argument)
{
    if (argument.kind == OPERAND_REGISTER)
    {
        return code_generator_register(rules, file, argument.which, argument.number);
    }
    if (argument.kind == OPERAND_PHYSREG)
    {
        return rules->fixed[argument.which];
    }
    // a signed number is held as its two's complement word
    return ((argument.kind == OPERAND_SIGNED) && (argument.number >= 0x80000000u))
               ? ("-" + std::to_string(0u - argument.number))
               : std::to_string(argument.number);
}

// how many registers of the file one register of a bank takes: two for a bank of 64-bit registers, which the file
// holds as a pair, and one for the rest. The bank of immediates is a word's value written into a form and none of the
// file, so it is never moved
static unsigned int code_generator_takes(unsigned int bank)
{
    return ((bank == REGCLASS_WIDE) || (bank == REGCLASS_MEMBER)) ? 2u : 1u;
}

// The banks laid into one register file, from the counts the lane declared: each bank begins where the one before it
// ended, in the order the declarations come. A language whose banks are namespaces of their own leaves every bank at
// 0, which writes each register by its own number as it always was. The predicates are a file of their own on every
// language that has them, and are not laid with the rest. 0 where the banks run past what the file holds, the lane
// then written by nobody: every register from there on would be one the language has already pinned
static int code_generator_file(const CodeGenerator *generator, const std::vector<MachineInstr> &items,
                               RegisterFile *file)
{
    for (unsigned int bank = 0u; bank < REGCLASS_COUNT; bank += 1u)
    {
        file->at[bank] = 0u;
        file->takes[bank] = 1u;
    }
    const unsigned int holds = generator->register_file_holds();
    if (holds == 0u)
    {
        return 1;
    }
    // each bank's count is the argument of the form that declares it, in the order the lane's declarations are written
    const unsigned int declares[] = {OPCODE_DECLARE_FILE,        OPCODE_DECLARE_SIGNS, OPCODE_DECLARE_OUT,
                                     OPCODE_DECLARE_ATOMS,       OPCODE_DECLARE_TEMPORARIES,
                                     OPCODE_DECLARE_WIDES,       OPCODE_DECLARE_MEMBERS};
    const unsigned int banks[] = {REGCLASS_FILE,      REGCLASS_SIGN, REGCLASS_OUT,   REGCLASS_ATOM,
                                  REGCLASS_TEMPORARY, REGCLASS_WIDE, REGCLASS_MEMBER};
    unsigned int at = 0u;
    for (unsigned int which = 0u; which < (sizeof(banks) / sizeof(banks[0])); which += 1u)
    {
        unsigned int count = 0u;
        for (const MachineInstr &item : items)
        {
            count = (item.form == declares[which]) ? item.arguments[0].number : count;
        }
        file->at[banks[which]] = at;
        file->takes[banks[which]] = code_generator_takes(banks[which]);
        at += count * file->takes[banks[which]];
    }
    return (at <= holds) ? 1 : 0;
}

// a form the core decided, written in the ruleset into `text`: its arguments, the program's note's from its step count
// and the target, the resident's from the launch's layout, a construct's scratch taken from where the core left each
// bank as it decided the form. `broken` set where the ruleset cannot write it
static void code_generator_text(const Ruleset *rules, const RegisterFile *file, const TargetInfo *target,
                                const MachineInstr &item, std::string &text, int *broken)
{
    std::vector<std::string> arguments;
    if (item.form == OPCODE_PROGRAM_NOTE)
    {
        char block[32];
        snprintf(block, sizeof(block), "%016llx", target->block_hash);
        // a device's compute capability and NVRTC's version are small counts, never negative
        arguments = {std::to_string(item.arguments[0].number),
                     std::to_string((unsigned long long)target->major),
                     std::to_string((unsigned long long)target->minor),
                     std::to_string((unsigned long long)target->nvrtc_major),
                     std::to_string((unsigned long long)target->nvrtc_minor),
                     std::string(block)};
    }
    else if (item.form == OPCODE_PROGRAM_UNIT)
    {
        for (unsigned int at = 0u; at < PROGRAM_UNIT_PARAMETERS; at += 1u)
        {
            arguments.push_back(std::to_string(codegen_unit(at)));
        }
    }
    else
    {
        for (unsigned int at = 0u; (at < item.count) && (at < MACHINE_INSTR_OPERANDS); at += 1u)
        {
            arguments.push_back(code_generator_argument(rules, file, item.arguments[at]));
        }
    }
    unsigned int taken[3] = {item.scratch[0], item.scratch[1], item.scratch[2]};
    const unsigned int banks[3] = {REGCLASS_TEMPORARY, REGCLASS_WIDE, REGCLASS_PREDICATE};
    const ScratchRegisters scratch = [rules, file, &taken, &banks](unsigned int bank) {
        for (unsigned int bank_index = 0u; bank_index < 3u; bank_index += 1u)
        {
            if (bank == banks[bank_index])
            {
                taken[bank_index] += 1u;
                return code_generator_register(rules, file, bank, taken[bank_index] - 1u);
            }
        }
        return std::string();
    };
    ruleset_write_list(rules, text, item.form, arguments, scratch, broken);
}

// forms `decide` decides, into items of their own: counted first on a copy of the lane, then decided into as many items
// as were counted: the lane goes on from the second as from one decision
template <typename Decide>
static std::vector<MachineInstr> code_generator_decided(MachineFunction *lane, const Decide &decide)
{
    MachineFunction counting = *lane;
    counting.items = NULL;
    counting.capacity = 0ull;
    counting.count = 0ull;
    decide(&counting);
    std::vector<MachineInstr> items((size_t)counting.count);
    lane->items = items.data();
    lane->capacity = counting.count;
    lane->count = 0ull;
    decide(lane);
    lane->items = NULL;
    lane->capacity = 0ull;
    return items;
}

// the 32-bit words every lane holds throughout: %zero, %thread, %threads, %word_base, %word_stride and %sign_base, and
// the seven 64-bit %launch, %lane_number, %record, %index, %body, %bodies and %tables; each member's atom address adds
// two more
#define CODEGEN_KEPT_WORDS 20u

// the most 32-bit words the lane holds live at once, reckoned from the lifetimes its text gives ptxas: each value's
// limbs and sign from its step to its last reader, each record word from its first put to its last, each atom word from
// its first reader to its last, each step's own temporaries at that step (`step_words`), and the words every lane holds
// throughout
static unsigned int code_generator_live_max(const IrProgram *program, const std::vector<unsigned int> &step_words,
                                            const std::vector<unsigned int> &atom_last, unsigned int atoms)
{
    const unsigned int steps = program->step_count;
    std::vector<unsigned int> read_last(steps);
    for (unsigned int at = 0u; at < steps; at += 1u)
    {
        read_last[at] = at;
    }
    // every operand is an earlier step, and the readers seen in order leave each value's last one
    for (unsigned int at = 0u; at < steps; at += 1u)
    {
        const DeviceRecordStep *const step = &program->steps[at];
        if (codegen_reads_left(step->operation))
        {
            read_last[step->left] = at;
        }
        if (codegen_reads_right(step->operation))
        {
            read_last[step->right] = at;
        }
    }
    // the change in live words at each step, their count its running sum
    std::vector<long long> change((size_t)steps + 1u, 0ll);
    for (unsigned int at = 0u; at < steps; at += 1u)
    {
        const long long value = (long long)program->steps[at].limbs + 1ll;
        change[at] += value + (long long)step_words[at];
        change[read_last[at] + 1u] -= value;
        change[at + 1u] -= (long long)step_words[at];
    }
    for (unsigned int word = 0u; word < program->out_limbs; word += 1u)
    {
        if (program->put_last[word] != 0u)
        {
            change[program->put_first[word]] += 1ll;
            change[program->put_last[word]] -= 1ll;
        }
    }
    for (unsigned int atom = 0u; atom < atoms; atom += 1u)
    {
        if (program->atom_reader[atom] != steps)
        {
            change[program->atom_reader[atom]] += 1ll;
            change[(size_t)atom_last[atom] + 1u] -= 1ll;
        }
    }
    long long live = 0ll;
    long long maximum = 0ll;
    for (unsigned int at = 0u; at < steps; at += 1u)
    {
        live += change[at];
        maximum = (live > maximum) ? live : maximum;
    }
    // at most the file's limbs and signs, the record's words, the atoms' words and one step's temporaries, far under
    // 2^32
    return (unsigned int)maximum + CODEGEN_KEPT_WORDS + (2u * program->members);
}

// each language's schema, kept for the process: the lane's forms, banks and fixed registers, and the file, the
// toolchain and the header the language names. A deque keeps each where it was laid out as more are laid out
static std::deque<RulesetSchema> s_ruleset_schemas;

static std::mutex s_ruleset_schemas_mutex;

static const RulesetSchema *code_generator_schema(const char *file, const char *toolchain, const char *header)
{
    const std::lock_guard<std::mutex> lock(s_ruleset_schemas_mutex);
    s_ruleset_schemas.push_back({file, toolchain, header, s_opcode_names, OPCODE_COUNT, s_regclass_names,
                                 REGCLASS_COUNT, s_physreg_names, PHYSREG_COUNT});
    return &s_ruleset_schemas.back();
}

CodeGenerator::CodeGenerator(const char *file, const char *toolchain, const char *header, unsigned int write_ports,
                             int shared)
    : Target(code_generator_schema(file, toolchain, header)), write_ports(write_ports), shared(shared)
{
}

// A program's lane and its resident as the core decides them, into `items` in the text's order: the note, the header's
// place, held by an item of the form ASM_PRINTER_ALL_ONES, the lane's opening and declarations, the body's opening, the
// body and the end; the places a thread holds in shared memory (the file's where the language lays it out there, else
// 0), and the most words it holds live at once. The core decides the steps first, then the lane's own forms in the
// order they were always written. 0 where the ruleset is not read, a step is one the lane does not hold, or a form
// breaks the lane. With a schedule model, the body is split into states and `report` told how
int CodeGenerator::decide(const EngineRecordLayout *layout, const ScheduleModel *model, ScheduleReport *report,
                          unsigned int *places, unsigned int *live, std::vector<MachineInstr> *items)
{
    const Ruleset *const rules = ready();
    if (rules == NULL)
    {
        return 0;
    }
    const unsigned int steps = layout->steps;
    const unsigned int scratch_banks[3] = {REGCLASS_TEMPORARY, REGCLASS_WIDE, REGCLASS_PREDICATE};
    std::vector<unsigned int> scratch;
    ruleset_scratch(rules, scratch_banks, &scratch);
    // the program as every step reads it: each record word's first and last put, and each atom word's first and last
    // reader, found before any step is decided
    std::vector<unsigned int> put_first(layout->out_limbs, 0u);
    std::vector<unsigned int> put_last(layout->out_limbs, 0u);
    IrProgram program{};
    program.steps = layout->step_table;
    program.step_count = steps;
    program.members = layout->members;
    program.file_limbs = layout->file_limbs;
    program.out_limbs = layout->out_limbs;
    unsigned int atoms = 0u;
    for (unsigned int member = 0u; member < ENGINE_RECORD_MEMBERS_MAX; member += 1u)
    {
        program.in_limbs[member] = layout->in_limbs[member];
        program.atom_first[member] = atoms;
        atoms += (member < layout->members) ? layout->in_limbs[member] : 0u;
    }
    for (unsigned int at = 0u; at < steps; at += 1u)
    {
        unsigned int low = 0u;
        unsigned int high = 0u;
        codegen_put_words(&program, &layout->step_table[at], &low, &high);
        for (unsigned int word = low; word < high; word += 1u)
        {
            put_first[word] = (put_last[word] == 0u) ? at : put_first[word];
            put_last[word] = at + 1u;
        }
    }
    std::vector<unsigned int> atom_reader(atoms, steps);
    std::vector<unsigned int> atom_last(atoms, 0u);
    for (unsigned int at = 0u; at < steps; at += 1u)
    {
        unsigned int low = 0u;
        unsigned int high = 0u;
        codegen_atom_words(&program, at, &low, &high);
        for (unsigned int word = low; word < high; word += 1u)
        {
            const unsigned int atom = program.atom_first[layout->step_table[at].member] + word;
            atom_reader[atom] = (atom_reader[atom] == steps) ? at : atom_reader[atom];
            atom_last[atom] = at;
        }
    }
    program.put_first = put_first.data();
    program.put_last = put_last.data();
    program.atom_reader = atom_reader.data();
    program.scratch = scratch.data();
    MachineFunction lane{};
    lane.program = &program;
    // the lane's opening takes %t0 and %w0 before any step does
    lane.temps_max = 1u;
    lane.wides_max = 1u;
    // the steps, each from the loop number the steps before it left
    std::vector<MachineInstr> stepped;
    std::vector<unsigned int> errors(steps, 0u);
    std::vector<unsigned int> step_words(steps, 0u);
    for (unsigned int at = 0u; at < steps; at += 1u)
    {
        int ok = 0;
        const std::vector<MachineInstr> step =
            code_generator_decided(&lane, [at, &ok](MachineFunction *deciding) { ok = codegen_step(deciding, at); });
        if (ok == 0)
        {
            return 0;
        }
        stepped.insert(stepped.end(), step.begin(), step.end());
        errors[at] = lane.errors;
        // a 64-bit temporary takes two words
        step_words[at] = lane.temps + (2u * lane.wides);
    }
    // the lane calls nothing; it holds places in shared memory only where its language lays out the file there
    *places = (shared != 0) ? layout->file_limbs : 0u;
    const unsigned int place_count = *places;
    const unsigned int *const error = errors.data();
    const unsigned int tables = lane.tables;
    const std::vector<MachineInstr> noted =
        code_generator_decided(&lane, [](MachineFunction *deciding) { codegen_note(deciding); });
    const std::vector<MachineInstr> opening_lane =
        code_generator_decided(&lane, [](MachineFunction *deciding) { codegen_instr0(deciding, OPCODE_LANE_OPEN); });
    const std::vector<MachineInstr> declarations =
        code_generator_decided(&lane, [atoms](MachineFunction *deciding) { codegen_declare(deciding, atoms); });
    const std::vector<MachineInstr> opened =
        code_generator_decided(&lane, [error, tables, place_count](MachineFunction *deciding) {
            codegen_open(deciding, error, tables, place_count);
        });
    const std::vector<MachineInstr> closed =
        code_generator_decided(&lane, [error](MachineFunction *deciding) { codegen_close(deciding, error); });
    // the body's forms in the text's order, between the forms that open it and those that end the lane
    std::vector<MachineInstr> body_open;
    std::vector<MachineInstr> body;
    if (model == NULL)
    {
        body_open =
            code_generator_decided(&lane, [](MachineFunction *deciding) { codegen_body_open(deciding, 0, 0u); });
        const std::vector<MachineInstr> *const parts[3] = {&opened, &stepped, &closed};
        for (const std::vector<MachineInstr> *part : parts)
        {
            body.insert(body.end(), part->begin(), part->end());
        }
    }
    else
    {
        // each form's cost; an error's label for the opening and one for each step at most, and each loop the steps
        // wrote
        const ScheduleCosts costs = schedule_costs(*model);
        std::vector<MachineOperand> dispatch_error((size_t)steps + 1u);
        std::vector<unsigned int> dispatch_state((size_t)steps + 1u, 0u);
        std::vector<unsigned int> loop_state((size_t)lane.loops + 1u, 0u);
        Schedule schedule{};
        schedule.cost = costs.cost.data();
        schedule.budget = costs.budget;
        schedule.dispatch_error = dispatch_error.data();
        schedule.dispatch_state = dispatch_state.data();
        schedule.dispatch_max = steps + 1u;
        schedule.loop_state = loop_state.data();
        schedule.loop_count = lane.loops;
        const unsigned int writes = costs.writes;
        const unsigned int ports = costs.ports;
        body = code_generator_decided(
            &lane, [&schedule, writes, ports, &opened, &stepped, &closed](MachineFunction *deciding) {
                codegen_schedule_open(deciding, &schedule, writes, ports);
                const std::vector<MachineInstr> *const parts[3] = {&opened, &stepped, &closed};
                for (const std::vector<MachineInstr> *part : parts)
                {
                    for (const MachineInstr &item : *part)
                    {
                        codegen_schedule_instr(deciding, &schedule, &item);
                    }
                }
                codegen_schedule_close(deciding, &schedule);
            });
        const unsigned int states = schedule.state;
        body_open = code_generator_decided(
            &lane, [states](MachineFunction *deciding) { codegen_body_open(deciding, 1, states); });
        report->states = schedule.state;
        report->maximum = schedule.maximum;
        report->over = schedule.over;
    }
    const std::vector<MachineInstr> ending =
        code_generator_decided(&lane, [](MachineFunction *deciding) { codegen_end(deciding); });
    if (lane.broken != 0u)
    {
        return 0;
    }
    // the header's place, which no form of the ruleset writes
    MachineInstr header{};
    header.form = ASM_PRINTER_ALL_ONES;
    header.arguments[0] = codegen_zero();
    header.arguments[1] = codegen_zero();
    header.arguments[2] = codegen_zero();
    header.arguments[3] = codegen_zero();
    items->clear();
    items->reserve(noted.size() + 1u + opening_lane.size() + declarations.size() + body_open.size() + body.size() +
                   ending.size());
    items->insert(items->end(), noted.begin(), noted.end());
    items->push_back(header);
    const std::vector<MachineInstr> *const parts[5] = {&opening_lane, &declarations, &body_open, &body, &ending};
    for (const std::vector<MachineInstr> *part : parts)
    {
        items->insert(items->end(), part->begin(), part->end());
    }
    *live = code_generator_live_max(&program, step_words, atom_last, atoms);
    return 1;
}

// the lane as decide() decides it, written in the ruleset under `header` for `target`, which the note names; empty
// where it is not decided, its banks run past the language's register file, or a form was written with other
// arguments than it takes
std::string CodeGenerator::lane(const EngineRecordLayout *layout, const TargetInfo *target, const std::string &header,
                                unsigned int *places, unsigned int *live, const ScheduleModel *model,
                                ScheduleReport *report)
{
    std::vector<MachineInstr> items;
    if (decide(layout, model, report, places, live, &items) == 0)
    {
        return std::string();
    }
    const Ruleset *const rules = ready();
    RegisterFile file;
    if (code_generator_file(this, items, &file) == 0)
    {
        return std::string();
    }
    int broken = 0;
    std::string text;
    for (const MachineInstr &item : items)
    {
        if (item.form == ASM_PRINTER_ALL_ONES)
        {
            text += header;
        }
        else
        {
            code_generator_text(rules, &file, target, item, text, &broken);
        }
    }
    return (broken != 0) ? std::string() : text;
}

// each form's cost by its name in the model, and the model's cost for a form it does not name
ScheduleCosts CodeGenerator::schedule_costs(const ScheduleModel &model) const
{
    ScheduleCosts costs;
    costs.cost.assign(OPCODE_COUNT, model.other);
    for (unsigned int form = 0u; form < OPCODE_COUNT; form += 1u)
    {
        const auto found = model.cost.find(std::string(s_opcode_names[form].text));
        costs.cost[form] = (found == model.cost.end()) ? model.other : found->second;
    }
    costs.budget = model.budget;
    costs.writes = model.writes;
    costs.ports = write_ports;
    return costs;
}
