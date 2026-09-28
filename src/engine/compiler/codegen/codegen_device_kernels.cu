// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// codegen_device_kernels.cu: the code generator's kernels: layout, counts, prologue and epilogue, schedule, record
// tables
#include "codegen_device_internal.h"

int layout_same(const EngineRecordLayout *left, const EngineRecordLayout *right)
{
    int same = (left->steps == right->steps) && (left->members == right->members) &&
               (left->file_limbs == right->file_limbs) && (left->out_bits == right->out_bits) &&
               (left->out_limbs == right->out_limbs) && (left->table_word_count == right->table_word_count);
    for (unsigned int member = 0u; member < ENGINE_RECORD_MEMBERS_MAX; member += 1u)
    {
        same = same && (left->in_limbs[member] == right->in_limbs[member]);
    }
    same = same && (memcmp(left->step_table, right->step_table, (size_t)left->steps * sizeof(DeviceRecordStep)) == 0);
    return same &&
           ((left->table_word_count == 0ull) || (memcmp(left->table_values, right->table_values,
                                                        (size_t)left->table_word_count * sizeof(unsigned int)) == 0));
}
#if (defined(__CUDACC__))

__global__ void codegen_device_fill(unsigned int *to, unsigned long long count, unsigned int value)
{
    const unsigned long long at = codegen_device_thread();
    if (at < count)
    {
        to[at] = value;
    }
}

// what each step reads from outside itself, a thread a step: each record word's first put and 1 past its last, each
// atom word's first reader, and the loops the step writes, whose running sum is the loop number each step begins at
__global__ void codegen_device_facts(IrProgram program, unsigned int *put_first, unsigned int *put_last,
                                     unsigned int *atom_reader, unsigned int *loops)
{
    const unsigned long long thread = codegen_device_thread();
    if (thread >= program.step_count)
    {
        return;
    }
    // below the step count, a 32-bit count
    const unsigned int at = (unsigned int)thread;
    unsigned int low = 0u;
    unsigned int high = 0u;
    codegen_put_words(&program, &program.steps[at], &low, &high);
    for (unsigned int word = low; word < high; word += 1u)
    {
        atomicMin(&put_first[word], at);
        atomicMax(&put_last[word], at + 1u);
    }
    codegen_atom_words(&program, at, &low, &high);
    for (unsigned int word = low; word < high; word += 1u)
    {
        atomicMin(&atom_reader[program.atom_first[program.steps[at].member] + word], at);
    }
    loops[at] = codegen_loops(&program, at);
}

// a word no put writes has its first put at 0, as the host sets it
__global__ void codegen_device_unlaid(unsigned int *put_first, const unsigned int *put_last, unsigned int words)
{
    const unsigned long long at = codegen_device_thread();
    if ((at < words) && (put_last[at] == 0u))
    {
        put_first[at] = 0u;
    }
}

// each step's forms counted, a thread a step, from the loop number it begins at, and what it leaves for the lane's own
// forms gathered: the most of each bank, the tables, a broken form or a step the lane does not hold, and the last
// step's banks
__global__ void codegen_device_count(IrProgram program, const unsigned int *loop_first, unsigned long long *counts,
                                     unsigned int *errors, unsigned int *summary)
{
    const unsigned long long thread = codegen_device_thread();
    if (thread >= program.step_count)
    {
        return;
    }
    const unsigned int at = (unsigned int)thread;
    MachineFunction lane{};
    lane.program = &program;
    lane.loops = loop_first[at];
    const int ok = codegen_step(&lane, at);
    counts[at] = lane.count;
    errors[at] = lane.errors;
    atomicMax(&summary[CODEGEN_TEMPS_MAX], lane.temps_max);
    atomicMax(&summary[CODEGEN_WIDES_MAX], lane.wides_max);
    atomicMax(&summary[CODEGEN_PREDICATES_MAX], lane.predicates_max);
    atomicOr(&summary[CODEGEN_TABLES], lane.tables);
    atomicOr(&summary[CODEGEN_BROKEN], lane.broken);
    atomicOr(&summary[CODEGEN_UNHELD], (ok != 0) ? 0u : 1u);
    if ((at + 1u) == program.step_count)
    {
        summary[CODEGEN_TEMPS] = lane.temps;
        summary[CODEGEN_WIDES] = lane.wides;
        summary[CODEGEN_PREDICATES] = lane.predicates;
    }
}

// each step's forms written where the scan of the counts puts them, a thread a step, decided again as they were counted
__global__ void codegen_device_write(IrProgram program, const unsigned int *loop_first,
                                     const unsigned long long *counts, const unsigned long long *item_first,
                                     MachineInstr *items)
{
    const unsigned long long thread = codegen_device_thread();
    if (thread >= program.step_count)
    {
        return;
    }
    const unsigned int at = (unsigned int)thread;
    MachineFunction lane{};
    lane.program = &program;
    lane.loops = loop_first[at];
    lane.items = &items[item_first[at]];
    lane.capacity = counts[at];
    (void)codegen_step(&lane, at);
}

// the lane as the steps left it for its own forms: the last step's banks, the most of each any step took, whether any
// reads the tables, and the loops the steps wrote
__global__ void codegen_device_left(const unsigned int *summary, unsigned int loops, MachineFunction *lane_out)
{
    if (codegen_device_thread() != 0ull)
    {
        return;
    }
    MachineFunction lane{};
    lane.temps = summary[CODEGEN_TEMPS];
    lane.wides = summary[CODEGEN_WIDES];
    lane.predicates = summary[CODEGEN_PREDICATES];
    lane.temps_max = summary[CODEGEN_TEMPS_MAX];
    lane.wides_max = summary[CODEGEN_WIDES_MAX];
    lane.predicates_max = summary[CODEGEN_PREDICATES_MAX];
    lane.tables = summary[CODEGEN_TABLES];
    lane.loops = loops;
    *lane_out = lane;
}

// the lane's own forms in the order they are decided, the note, the lane's first form, the declarations, the opening,
// the close, then, after the schedule where the body is split, the body's opening and the end, since a construct's
// scratch goes on from where each bank stands: those from `first` to `last` of that order, in one thread, going on from
// the lane as `lane_out` holds it. Counted where `items` is NULL, each part's count laid out in `parts`; else written
// from `items` where `parts` puts each, with the header's item, which the assembly printer takes whole, where the note
// is written, and the lane left in `lane_out` for the forms decided after. `states` is the states the body was split
// into, 0 where it is not split
__global__ void codegen_prologue_epilogue(IrProgram program, const unsigned int *errors, unsigned int *summary,
                                          MachineFunction *lane_out, unsigned int atoms, unsigned int places,
                                          unsigned int first, unsigned int last, int scheduled, unsigned int states,
                                          CodegenParts *parts, MachineInstr *items)
{
    if (codegen_device_thread() != 0ull)
    {
        return;
    }
    MachineFunction lane = *lane_out;
    lane.program = &program;
    const unsigned int order[7] = {CODEGEN_NOTE,   CODEGEN_LANE_OPEN, CODEGEN_DECLARATIONS, CODEGEN_OPENED,
                                   CODEGEN_CLOSED, CODEGEN_BODY_OPEN, CODEGEN_ENDING};
    for (unsigned int decided = first; decided < last; decided += 1u)
    {
        const unsigned int part = order[decided];
        lane.items = (items != NULL) ? &items[parts->at[part]] : NULL;
        lane.capacity = (items != NULL) ? parts->count[part] : 0ull;
        lane.count = 0ull;
        if (part == CODEGEN_NOTE)
        {
            codegen_note(&lane);
        }
        else if (part == CODEGEN_LANE_OPEN)
        {
            codegen_instr0(&lane, OPCODE_LANE_OPEN);
        }
        else if (part == CODEGEN_DECLARATIONS)
        {
            codegen_declare(&lane, atoms);
        }
        else if (part == CODEGEN_OPENED)
        {
            codegen_open(&lane, errors, summary[CODEGEN_TABLES], places);
        }
        else if (part == CODEGEN_CLOSED)
        {
            codegen_close(&lane, errors);
        }
        else if (part == CODEGEN_BODY_OPEN)
        {
            codegen_body_open(&lane, scheduled, states);
        }
        else
        {
            codegen_end(&lane);
        }
        if (items == NULL)
        {
            parts->count[part] = lane.count;
        }
    }
    if ((items != NULL) && (first == 0u))
    {
        MachineInstr *const header = &items[parts->at[CODEGEN_HEADER]];
        const MachineOperand none = codegen_zero();
        header->form = ASM_PRINTER_ALL_ONES;
        header->count = 0u;
        for (unsigned int at = 0u; at < MACHINE_INSTR_OPERANDS; at += 1u)
        {
            header->arguments[at] = none;
        }
        header->scratch[0] = 0u;
        header->scratch[1] = 0u;
        header->scratch[2] = 0u;
    }
    if (items != NULL)
    {
        summary[CODEGEN_BROKEN] |= lane.broken;
        lane.program = NULL;
        lane.items = NULL;
        lane.capacity = 0ull;
        lane.count = 0ull;
        *lane_out = lane;
    }
}

// The body split into states, in one thread, going on from the lane as `lane_out` holds it: the body's forms,
// `body_count` of them from `body` in the order they run (the opening, the steps and the close), laid out into the
// schedule (codegen_schedule_instr), as the host's lane splits them. Counted where `items` is NULL; else written there
// and the lane left in `lane_out` for the forms decided after. How it was split in `ended`
__global__ void codegen_schedule(IrProgram program, unsigned int *summary, MachineFunction *lane_out, Schedule schedule,
                                 unsigned int writes, unsigned int ports, const MachineInstr *body,
                                 unsigned long long body_count, unsigned long long capacity, MachineInstr *items,
                                 ScheduleEnd *ended)
{
    if (codegen_device_thread() != 0ull)
    {
        return;
    }
    MachineFunction lane = *lane_out;
    lane.program = &program;
    lane.items = items;
    lane.capacity = (items != NULL) ? capacity : 0ull;
    lane.count = 0ull;
    codegen_schedule_open(&lane, &schedule, writes, ports);
    for (unsigned long long at = 0ull; at < body_count; at += 1ull)
    {
        codegen_schedule_instr(&lane, &schedule, &body[at]);
    }
    codegen_schedule_close(&lane, &schedule);
    ended->count = lane.count;
    ended->states = schedule.state;
    ended->maximum = schedule.maximum;
    ended->over = schedule.over;
    if (items != NULL)
    {
        summary[CODEGEN_BROKEN] |= lane.broken;
        lane.program = NULL;
        lane.items = NULL;
        lane.capacity = 0ull;
        lane.count = 0ull;
        *lane_out = lane;
    }
}

// the records each item takes, a thread an item; an item given other arguments than its form takes breaks the lane, as
// the host's writing it does
__global__ void codegen_device_record_counts(AsmPrinterLists forms, const MachineInstr *items,
                                             unsigned long long item_count, unsigned long long *record_counts,
                                             unsigned int *summary)
{
    const unsigned long long at = codegen_device_thread();
    if (at >= item_count)
    {
        return;
    }
    const int formed = asm_printer_formed(&items[at]);
    if (formed == 0)
    {
        atomicOr(&summary[CODEGEN_BROKEN], 1u);
    }
    record_counts[at] = (formed != 0) ? asm_printer_record_count(&forms, &items[at]) : 1ull;
}

// each item's records laid out, a thread an item (asm_printer_records)
__global__ void codegen_device_records(AsmPrinterLists forms, const MachineInstr *items, unsigned long long item_count,
                                       const unsigned long long *record_first, unsigned int *records,
                                       unsigned long long *record_lanes)
{
    const unsigned long long at = codegen_device_thread();
    if (at < item_count)
    {
        asm_printer_records(&forms, &items[at], record_first[at], records, record_lanes);
    }
}

// each record's first lane laid out, and the index that gives each of its lanes the record, a thread a record
__global__ void codegen_device_index(unsigned int *records, unsigned long long record_count,
                                     const unsigned long long *lane_first, const unsigned long long *record_lanes,
                                     unsigned int *index)
{
    const unsigned long long record = codegen_device_thread();
    if (record >= record_count)
    {
        return;
    }
    asm_printer_first(records, record, lane_first[record]);
    for (unsigned long long lane = 0ull; lane < record_lanes[record]; lane += 1ull)
    {
        // a record's number is below 2^31, as the host holds the records
        index[lane_first[record] + lane] = (unsigned int)record;
    }
}

// each lane's byte (asm_printer_byte), a thread a lane
__global__ void codegen_device_bytes(const unsigned int *out, unsigned long long lanes, unsigned int out_limbs,
                                     unsigned int offset, unsigned char *bytes)
{
    const unsigned long long lane = codegen_device_thread();
    if (lane < lanes)
    {
        // a byte, 8 bits
        bytes[lane] = (unsigned char)asm_printer_byte(&out[lane * out_limbs], out_limbs, offset);
    }
}

// keymath's encoding of the program, in one thread (keymath_core_record_encode)
__global__ void codegen_device_encode(KeymathCoreEncode encoding, LayoutEnd *ended)
{
    if (codegen_device_thread() != 0ull)
    {
        return;
    }
    ended->ok = keymath_core_record_encode(&encoding);
    ended->end = encoding.end;
    ended->at = encoding.at;
}
#endif
