// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "emit_lane.h"
#include "emit_core.h"
#include "emit_rules.h"

#include <stddef.h>
#include <stdio.h>

#include <deque>
#include <initializer_list>
#include <map>
#include <mutex>
#include <string>
#include <vector>

static const EmitRuleName s_emit_form_names[EMIT_FORM_COUNT] = {EMIT_FORMS(EMIT_FORM_WRITTEN)};

static const EmitRuleName s_emit_bank_names[EMIT_BANK_COUNT] = {EMIT_BANKS(EMIT_BANK_WRITTEN)};

static const EmitRuleName s_emit_fixed_names[EMIT_FIXED_COUNT] = {EMIT_FIXED(EMIT_FIXED_WRITTEN)};

// The record program as a register lane, in any language whose ruleset writes the lane's forms (PTX's is
// ptx.krs): each step unrolled at its widths into straight-line text over registers the lane holds itself. The
// file is a bank by place and its signs another, as key_schedule laid them; the record's words are a bank, laid
// by each put and each stored once the last put that lays it has run; the atoms' words are a bank, each loaded
// at its first reader. What a compiler would loop over a register's limbs is written out here limb by limb from
// the program's own widths. The emitter writes no text of its own: every line is a form of the language's
// ruleset, and every register a written form of its banks and fixed registers. The emitter decides what a step does
// and the ruleset how the language writes it. What each step does, and the lane's opening, close and cut into
// states, is decided in emit_core.h, which the device compiles as well; here the forms it decides are written in the
// ruleset and laid into the text in its order. The steps that loop on their values are loops of the same forms, each
// body over registers of fixed widths so no limb is named by a value the lane computes: the gcd, the golden ladder, a
// division by more than one limb, and a product too wide to unroll. A loop is a label and a branch back to it on a
// predicate, which a language that clocks the lane cuts into states that go back. The lane calls nothing and takes no
// shared memory. Every step is the interpreter's arithmetic limb for limb, branch-free where the interpreter branches
// on a sign or a borrow, and CYCLE_RECORD_CHECK=1 holds the two to each other. After the lane comes the program
// resident that runs its launch's lanes (program_unit), the kernel the record machine launches or a circuit's top.
// The text is the whole program, and nothing hand-written is linked with it.

// register `at` of a bank, as the ruleset writes it
static std::string emit_lane_register(const EmitRuleset *rules, unsigned int bank, unsigned int at)
{
    const EmitForm *const form = &rules->banks[bank];
    const std::string number = std::to_string(at);
    std::string name = form->pieces[0];
    for (size_t slot = 0u; slot < form->slots.size(); slot += 1u)
    {
        name += number;
        name += form->pieces[slot + 1u];
    }
    return name;
}

// an argument the core decided, as the ruleset writes it: a register by its bank, a held register by its name, and a
// number in decimal, a signed one with its minus
static std::string emit_lane_argument(const EmitRuleset *rules, const EmitCoreArgument &argument)
{
    if (argument.kind == EMIT_CORE_REGISTER)
    {
        return emit_lane_register(rules, argument.which, argument.number);
    }
    if (argument.kind == EMIT_CORE_FIXED)
    {
        return rules->fixed[argument.which];
    }
    // a signed number is held as its two's complement word
    return ((argument.kind == EMIT_CORE_SIGNED) && (argument.number >= 0x80000000u))
             ? ("-" + std::to_string(0u - argument.number))
             : std::to_string(argument.number);
}

// a form the core decided, written in the ruleset into `text`: its arguments, the program's note's from its step count
// and the target, the resident's from the launch's layout, a construct's scratch taken from where the core left each
// bank as it decided the form. `broken` set where the ruleset cannot write it
static void emit_lane_text(const EmitRuleset *rules, const EmitTarget *target, const EmitCoreItem &item,
                           std::string &text, int *broken)
{
    std::vector<std::string> arguments;
    if (item.form == EMIT_FORM_PROGRAM_NOTE)
    {
        char block[32];
        snprintf(block, sizeof(block), "%016llx", target->block_hash);
        // a device's compute capability and NVRTC's version are small counts, never negative
        arguments = {std::to_string(item.arguments[0].number), std::to_string((unsigned long long)target->major),
                     std::to_string((unsigned long long)target->minor),
                     std::to_string((unsigned long long)target->nvrtc_major),
                     std::to_string((unsigned long long)target->nvrtc_minor), std::string(block)};
    }
    else if (item.form == EMIT_FORM_PROGRAM_UNIT)
    {
        for (unsigned int at = 0u; at < EMIT_CORE_UNIT_PARAMETERS; at += 1u)
        {
            arguments.push_back(std::to_string(emit_core_unit(at)));
        }
    }
    else
    {
        for (unsigned int at = 0u; (at < item.count) && (at < EMIT_CORE_ARGUMENTS); at += 1u)
        {
            arguments.push_back(emit_lane_argument(rules, item.arguments[at]));
        }
    }
    unsigned int taken[3] = {item.scratch[0], item.scratch[1], item.scratch[2]};
    const unsigned int banks[3] = {EMIT_BANK_TEMPORARY, EMIT_BANK_WIDE, EMIT_BANK_PREDICATE};
    const EmitScratch scratch = [rules, &taken, &banks](unsigned int bank) {
        for (unsigned int held = 0u; held < 3u; held += 1u)
        {
            if (bank == banks[held])
            {
                taken[held] += 1u;
                return emit_lane_register(rules, bank, taken[held] - 1u);
            }
        }
        return std::string();
    };
    emit_ruleset_write_list(rules, text, item.form, arguments, scratch, broken);
}

// forms `decide` decides, into items of their own: counted first on a copy of the lane, then decided into as many items
// as were counted: the lane goes on from the second as from one decision
template <typename Decide>
static std::vector<EmitCoreItem> emit_lane_decided(EmitCoreLane *lane, const Decide &decide)
{
    EmitCoreLane counting = *lane;
    counting.items = NULL;
    counting.capacity = 0ull;
    counting.count = 0ull;
    decide(&counting);
    std::vector<EmitCoreItem> items((size_t)counting.count);
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
#define EMIT_LANE_HELD_WORDS 20u

// the most 32-bit words the lane holds live at once, reckoned from the lifetimes its text gives ptxas: each value's
// limbs and sign from its step to its last reader, each record word from its first put to its last, each atom word from
// its first reader to its last, each step's own temporaries at that step (`step_words`), and the words every lane holds
// throughout
static unsigned int emit_lane_live_most(const EmitCoreProgram *program, const std::vector<unsigned int> &step_words,
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
        if (emit_core_reads_left(step->operation))
        {
            read_last[step->left] = at;
        }
        if (emit_core_reads_right(step->operation))
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
    long long most = 0ll;
    for (unsigned int at = 0u; at < steps; at += 1u)
    {
        live += change[at];
        most = (live > most) ? live : most;
    }
    // at most the file's limbs and signs, the record's words, the atoms' words and one step's temporaries, far under 2^32
    return (unsigned int)most + EMIT_LANE_HELD_WORDS + (2u * program->members);
}

// each language's schema, held for the process: the lane's forms, banks and held registers, and the file, the
// toolchain and the header the language names. A deque keeps each where it was laid as more are laid
static std::deque<EmitRuleSchema> s_emit_lane_schemas;

static std::mutex s_emit_lane_schemas_held;

static const EmitRuleSchema *emit_lane_schema(const char *file, const char *toolchain, const char *header)
{
    const std::lock_guard<std::mutex> held(s_emit_lane_schemas_held);
    s_emit_lane_schemas.push_back({file, toolchain, header, s_emit_form_names, EMIT_FORM_COUNT, s_emit_bank_names,
                                    EMIT_BANK_COUNT, s_emit_fixed_names, EMIT_FIXED_COUNT});
    return &s_emit_lane_schemas.back();
}

EmitLane::EmitLane(const char *file, const char *toolchain, const char *header, unsigned int write_ports,
                             int shared)
    : Emitter(emit_lane_schema(file, toolchain, header)), write_ports(write_ports), shared(shared)
{
}

// A program's lane and its resident as the core decides them, into `items` in the text's order: the note, the header's
// place, held by an item of the form EMIT_TEXT_WHOLE, the lane's opening and declarations, the body's opening, the body
// and the end; the places a thread holds in shared memory (the file's where the language lays it there, else 0), and
// the most words it holds live at once. The core decides the steps first, then the lane's own forms in the order they
// were always written. 0 where the ruleset is not read, a step is one the lane does not hold, or a form breaks the
// lane. With a shape, the body is cut into states and `report` told how
int EmitLane::decide(const EngineRecordLayout *layout, const EmitLaneShape *shape, EmitLaneShaped *report,
                     unsigned int *places, unsigned int *live, std::vector<EmitCoreItem> *items)
{
    const EmitRuleset *const rules = ready();
    if (rules == NULL)
    {
        return 0;
    }
    const unsigned int steps = layout->steps;
    const unsigned int scratch_banks[3] = {EMIT_BANK_TEMPORARY, EMIT_BANK_WIDE, EMIT_BANK_PREDICATE};
    std::vector<unsigned int> scratch;
    emit_ruleset_scratch(rules, scratch_banks, &scratch);
    // the program as every step reads it: each record word's first and last put, and each atom word's first and last
    // reader, found before any step is decided
    std::vector<unsigned int> put_first(layout->out_limbs, 0u);
    std::vector<unsigned int> put_last(layout->out_limbs, 0u);
    EmitCoreProgram program{};
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
        emit_core_put_words(&program, &layout->step_table[at], &low, &high);
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
        emit_core_atom_words(&program, at, &low, &high);
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
    EmitCoreLane lane{};
    lane.program = &program;
    // the lane's opening takes %t0 and %w0 before any step does
    lane.temps_most = 1u;
    lane.wides_most = 1u;
    // the steps, each from the loop number the steps before it left
    std::vector<EmitCoreItem> stepped;
    std::vector<unsigned int> refuses(steps, 0u);
    std::vector<unsigned int> step_words(steps, 0u);
    for (unsigned int at = 0u; at < steps; at += 1u)
    {
        int held = 0;
        const std::vector<EmitCoreItem> step =
            emit_lane_decided(&lane, [at, &held](EmitCoreLane *deciding) { held = emit_core_step(deciding, at); });
        if (held == 0)
        {
            return 0;
        }
        stepped.insert(stepped.end(), step.begin(), step.end());
        refuses[at] = lane.refuses;
        // a 64-bit temporary takes two words
        step_words[at] = lane.temps + (2u * lane.wides);
    }
    // the lane calls nothing; it holds places in shared memory only where its language lays the file there
    *places = (shared != 0) ? layout->file_limbs : 0u;
    const unsigned int held_places = *places;
    const unsigned int *const refused = refuses.data();
    const unsigned int tables = lane.tables;
    const std::vector<EmitCoreItem> noted = emit_lane_decided(&lane, [](EmitCoreLane *deciding) {
        emit_core_note(deciding);
    });
    const std::vector<EmitCoreItem> opening_lane = emit_lane_decided(&lane, [](EmitCoreLane *deciding) {
        emit_core_form0(deciding, EMIT_FORM_LANE_OPEN);
    });
    const std::vector<EmitCoreItem> declarations = emit_lane_decided(&lane, [atoms](EmitCoreLane *deciding) {
        emit_core_declare(deciding, atoms);
    });
    const std::vector<EmitCoreItem> opened =
        emit_lane_decided(&lane, [refused, tables, held_places](EmitCoreLane *deciding) {
            emit_core_open(deciding, refused, tables, held_places);
        });
    const std::vector<EmitCoreItem> closed = emit_lane_decided(&lane, [refused](EmitCoreLane *deciding) {
        emit_core_close(deciding, refused);
    });
    // the body's forms in the text's order, between the forms that open it and those that end the lane
    std::vector<EmitCoreItem> body_open;
    std::vector<EmitCoreItem> body;
    if (shape == NULL)
    {
        body_open = emit_lane_decided(&lane, [](EmitCoreLane *deciding) { emit_core_body_open(deciding, 0, 0u); });
        const std::vector<EmitCoreItem> *const parts[3] = {&opened, &stepped, &closed};
        for (const std::vector<EmitCoreItem> *part : parts)
        {
            body.insert(body.end(), part->begin(), part->end());
        }
    }
    else
    {
        // each form's cost; a refusal's label for the opening and one for each step at most, and each loop the steps
        // wrote
        const EmitLaneCut laid = cut(*shape);
        std::vector<EmitCoreArgument> dispatch_refusal((size_t)steps + 1u);
        std::vector<unsigned int> dispatch_state((size_t)steps + 1u, 0u);
        std::vector<unsigned int> loop_state((size_t)lane.loops + 1u, 0u);
        EmitCoreCut cut{};
        cut.cost = laid.cost.data();
        cut.budget = laid.budget;
        cut.dispatch_refusal = dispatch_refusal.data();
        cut.dispatch_state = dispatch_state.data();
        cut.dispatch_most = steps + 1u;
        cut.loop_state = loop_state.data();
        cut.loop_count = lane.loops;
        const unsigned int writes = laid.writes;
        const unsigned int ports = laid.ports;
        body = emit_lane_decided(&lane, [&cut, writes, ports, &opened, &stepped, &closed](EmitCoreLane *deciding) {
            emit_core_cut_open(deciding, &cut, writes, ports);
            const std::vector<EmitCoreItem> *const parts[3] = {&opened, &stepped, &closed};
            for (const std::vector<EmitCoreItem> *part : parts)
            {
                for (const EmitCoreItem &item : *part)
                {
                    emit_core_cut_item(deciding, &cut, &item);
                }
            }
            emit_core_cut_close(deciding, &cut);
        });
        const unsigned int states = cut.state;
        body_open = emit_lane_decided(&lane, [states](EmitCoreLane *deciding) {
            emit_core_body_open(deciding, 1, states);
        });
        report->states = cut.state;
        report->most = cut.most;
        report->over = cut.over;
    }
    const std::vector<EmitCoreItem> ending = emit_lane_decided(&lane, [](EmitCoreLane *deciding) {
        emit_core_end(deciding);
    });
    if (lane.broken != 0u)
    {
        return 0;
    }
    // the header's place, which no form of the ruleset writes
    EmitCoreItem header{};
    header.form = EMIT_TEXT_WHOLE;
    header.arguments[0] = emit_core_zero();
    header.arguments[1] = emit_core_zero();
    header.arguments[2] = emit_core_zero();
    header.arguments[3] = emit_core_zero();
    items->clear();
    items->reserve(noted.size() + 1u + opening_lane.size() + declarations.size() + body_open.size() + body.size()
                   + ending.size());
    items->insert(items->end(), noted.begin(), noted.end());
    items->push_back(header);
    const std::vector<EmitCoreItem> *const parts[5] = {&opening_lane, &declarations, &body_open, &body, &ending};
    for (const std::vector<EmitCoreItem> *part : parts)
    {
        items->insert(items->end(), part->begin(), part->end());
    }
    *live = emit_lane_live_most(&program, step_words, atom_last, atoms);
    return 1;
}

// the lane as decide() decides it, written in the ruleset under `header` for `target`, which the note names; empty where
// it is not decided, or a form was written with other arguments than it takes
std::string EmitLane::lane(const EngineRecordLayout *layout, const EmitTarget *target,
                           const std::string &header, unsigned int *places, unsigned int *live,
                           const EmitLaneShape *shape, EmitLaneShaped *report)
{
    std::vector<EmitCoreItem> items;
    if (decide(layout, shape, report, places, live, &items) == 0)
    {
        return std::string();
    }
    const EmitRuleset *const rules = ready();
    int broken = 0;
    std::string text;
    for (const EmitCoreItem &item : items)
    {
        if (item.form == EMIT_TEXT_WHOLE)
        {
            text += header;
        }
        else
        {
            emit_lane_text(rules, target, item, text, &broken);
        }
    }
    return (broken != 0) ? std::string() : text;
}

std::string EmitLane::program(const EngineRecordLayout *layout, const EmitTarget *target,
                              const std::string &header, unsigned int *places, unsigned int *live)
{
    EmitLaneShaped report{};
    return lane(layout, target, header, places, live, program_shape(), &report);
}

const EmitLaneShape *EmitLane::program_shape(void) const
{
    return NULL;
}

int EmitLane::program_cut(EmitLaneCut *laid) const
{
    const EmitLaneShape *const shape = program_shape();
    if (shape == NULL)
    {
        return 0;
    }
    *laid = cut(*shape);
    return 1;
}

std::string EmitLane::shaped(const EngineRecordLayout *layout, const EmitTarget *target,
                             const std::string &header, unsigned int *places, unsigned int *live,
                             const EmitLaneShape &shape, EmitLaneShaped *report)
{
    return lane(layout, target, header, places, live, &shape, report);
}

int EmitLane::decided(const EngineRecordLayout *layout, unsigned int *places, std::vector<EmitCoreItem> *items)
{
    unsigned int live = 0u;
    EmitLaneShaped report{};
    return decide(layout, program_shape(), &report, places, &live, items);
}

int EmitLane::decided(const EngineRecordLayout *layout, const EmitLaneShape &shape, EmitLaneShaped *report,
                      unsigned int *places, std::vector<EmitCoreItem> *items)
{
    unsigned int live = 0u;
    return decide(layout, &shape, report, places, &live, items);
}

// each form's cost by its name in the shape, and the shape's cost for a form it does not name
EmitLaneCut EmitLane::cut(const EmitLaneShape &shape) const
{
    EmitLaneCut laid;
    laid.cost.assign(EMIT_FORM_COUNT, shape.other);
    for (unsigned int form = 0u; form < EMIT_FORM_COUNT; form += 1u)
    {
        const auto found = shape.cost.find(std::string(s_emit_form_names[form].text));
        laid.cost[form] = (found == shape.cost.end()) ? shape.other : found->second;
    }
    laid.budget = shape.budget;
    laid.writes = shape.writes;
    laid.ports = write_ports;
    return laid;
}
