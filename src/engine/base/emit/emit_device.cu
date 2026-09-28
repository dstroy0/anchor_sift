// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "emit_device.h"
#include "../cycle/cycle.h"
#include "../key_schedule/key_schedule.h"
#include "../key_schedule/key_schedule_core.h"
#include "../keymath/keymath_core.h"

#include <stddef.h>
#include <stdlib.h>
#include <string.h>

#include <string>
#include <vector>

int emit_lay_same(const EngineRecordLayout *left, const EngineRecordLayout *right)
{
    int same = (left->steps == right->steps) && (left->members == right->members)
            && (left->file_limbs == right->file_limbs) && (left->out_bits == right->out_bits)
            && (left->out_limbs == right->out_limbs) && (left->table_word_count == right->table_word_count);
    for (unsigned int member = 0u; member < ENGINE_RECORD_MEMBERS_MAX; member += 1u)
    {
        same = same && (left->in_limbs[member] == right->in_limbs[member]);
    }
    same = same && (memcmp(left->step_table, right->step_table, (size_t)left->steps * sizeof(DeviceRecordStep)) == 0);
    return same
        && ((left->table_word_count == 0ull)
            || (memcmp(left->table_values, right->table_values,
                       (size_t)left->table_word_count * sizeof(unsigned int)) == 0));
}

#if defined(__CUDACC__)
#include <cub/cub.cuh>
#include <cuda_runtime.h>

// the threads a block of the emitter's kernels runs
#define EMIT_THREADS 256u

// the most a scan or a selection counts, as cub takes its counts
#define EMIT_COUNT_MOST 0x7FFFFFFFull

// what the steps leave for the lane's own forms, a word each: the most temporaries, 64-bit temporaries and predicates
// any step took, 1 where any reads the tables, where a form breaks the lane and where a step is one the lane does not
// hold, and what the last step left taken in each bank, which the lane's own forms go on from
enum EmitSummary
{
    EMIT_TEMPS_MOST = 0,
    EMIT_WIDES_MOST = 1,
    EMIT_PREDICATES_MOST = 2,
    EMIT_TABLES = 3,
    EMIT_BROKEN = 4,
    EMIT_UNHELD = 5,
    EMIT_TEMPS = 6,
    EMIT_WIDES = 7,
    EMIT_PREDICATES = 8,
    EMIT_SUMMARY = 9
};

// the lane's parts in the text's order: the note, the header, the lane's opening and declarations, the body's opening,
// the body (its opening, the steps and its close), and the lane's end
enum EmitPart
{
    EMIT_NOTE = 0,
    EMIT_HEADER = 1,
    EMIT_LANE_OPEN = 2,
    EMIT_DECLARATIONS = 3,
    EMIT_BODY_OPEN = 4,
    EMIT_OPENED = 5,
    EMIT_STEPPED = 6,
    EMIT_CLOSED = 7,
    EMIT_ENDING = 8,
    EMIT_PARTS = 9
};

// where each part's items begin among the lane's, and how many it holds
struct EmitParts
{
    unsigned long long at[EMIT_PARTS];
    unsigned long long count[EMIT_PARTS];
};

// a byte the text program wrote that is not 0, which the text holds
struct EmitNonzeroByte
{
    __host__ __device__ bool operator()(const unsigned char &byte) const
    {
        return byte != 0u;
    }
};

// the thread's place across the grid
__device__ static unsigned long long emit_thread(void)
{
    return ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x;
}

__global__ static void emit_fill(unsigned int *to, unsigned long long count, unsigned int value)
{
    const unsigned long long at = emit_thread();
    if (at < count)
    {
        to[at] = value;
    }
}

// what each step reads from outside itself, a thread a step: each record word's first put and 1 past its last, each
// atom word's first reader, and the loops the step writes, whose running sum is the loop number each step begins at
__global__ static void emit_facts(EmitCoreProgram program, unsigned int *put_first, unsigned int *put_last,
                                  unsigned int *atom_reader, unsigned int *loops)
{
    const unsigned long long thread = emit_thread();
    if (thread >= program.step_count)
    {
        return;
    }
    // below the step count, a 32-bit count
    const unsigned int at = (unsigned int)thread;
    unsigned int low = 0u;
    unsigned int high = 0u;
    emit_core_put_words(&program, &program.steps[at], &low, &high);
    for (unsigned int word = low; word < high; word += 1u)
    {
        atomicMin(&put_first[word], at);
        atomicMax(&put_last[word], at + 1u);
    }
    emit_core_atom_words(&program, at, &low, &high);
    for (unsigned int word = low; word < high; word += 1u)
    {
        atomicMin(&atom_reader[program.atom_first[program.steps[at].member] + word], at);
    }
    loops[at] = emit_core_loops(&program, at);
}

// a word no put lays has its first put at 0, as the host lays it
__global__ static void emit_unlaid(unsigned int *put_first, const unsigned int *put_last, unsigned int words)
{
    const unsigned long long at = emit_thread();
    if ((at < words) && (put_last[at] == 0u))
    {
        put_first[at] = 0u;
    }
}

// each step's forms counted, a thread a step, from the loop number it begins at, and what it leaves for the lane's own
// forms gathered: the most of each bank, the tables, a broken form or a step the lane does not hold, and the last step's
// banks
__global__ static void emit_count(EmitCoreProgram program, const unsigned int *loop_first,
                                  unsigned long long *counts, unsigned int *refuses, unsigned int *summary)
{
    const unsigned long long thread = emit_thread();
    if (thread >= program.step_count)
    {
        return;
    }
    const unsigned int at = (unsigned int)thread;
    EmitCoreLane lane{};
    lane.program = &program;
    lane.loops = loop_first[at];
    const int held = emit_core_step(&lane, at);
    counts[at] = lane.count;
    refuses[at] = lane.refuses;
    atomicMax(&summary[EMIT_TEMPS_MOST], lane.temps_most);
    atomicMax(&summary[EMIT_WIDES_MOST], lane.wides_most);
    atomicMax(&summary[EMIT_PREDICATES_MOST], lane.predicates_most);
    atomicOr(&summary[EMIT_TABLES], lane.tables);
    atomicOr(&summary[EMIT_BROKEN], lane.broken);
    atomicOr(&summary[EMIT_UNHELD], (held != 0) ? 0u : 1u);
    if ((at + 1u) == program.step_count)
    {
        summary[EMIT_TEMPS] = lane.temps;
        summary[EMIT_WIDES] = lane.wides;
        summary[EMIT_PREDICATES] = lane.predicates;
    }
}

// each step's forms written where the scan of the counts puts them, a thread a step, decided again as they were counted
__global__ static void emit_write(EmitCoreProgram program, const unsigned int *loop_first,
                                  const unsigned long long *counts, const unsigned long long *item_first,
                                  EmitCoreItem *items)
{
    const unsigned long long thread = emit_thread();
    if (thread >= program.step_count)
    {
        return;
    }
    const unsigned int at = (unsigned int)thread;
    EmitCoreLane lane{};
    lane.program = &program;
    lane.loops = loop_first[at];
    lane.items = &items[item_first[at]];
    lane.capacity = counts[at];
    (void)emit_core_step(&lane, at);
}

// the lane as the steps left it for its own forms: the last step's banks, the most of each any step took, whether any
// reads the tables, and the loops the steps wrote
__global__ static void emit_left(const unsigned int *summary, unsigned int loops, EmitCoreLane *held)
{
    if (emit_thread() != 0ull)
    {
        return;
    }
    EmitCoreLane lane{};
    lane.temps = summary[EMIT_TEMPS];
    lane.wides = summary[EMIT_WIDES];
    lane.predicates = summary[EMIT_PREDICATES];
    lane.temps_most = summary[EMIT_TEMPS_MOST];
    lane.wides_most = summary[EMIT_WIDES_MOST];
    lane.predicates_most = summary[EMIT_PREDICATES_MOST];
    lane.tables = summary[EMIT_TABLES];
    lane.loops = loops;
    *held = lane;
}

// the lane's own forms in the order they are decided, the note, the lane's first form, the declarations, the opening,
// the close, then, after the cut where the body is cut, the body's opening and the end, since a construct's scratch goes
// on from where each bank stands: those from `first` to `last` of that order, in one thread, going on from the lane as
// `held` holds it. Counted where `items` is NULL, each part's count laid in `parts`; else written from `items` where
// `parts` puts each, with the header's item, which the text program takes whole, where the note is written, and the lane
// left in `held` for the forms decided after. `states` is the states the body was cut into, 0 where it is not cut
__global__ static void emit_tail(EmitCoreProgram program, const unsigned int *refuses, unsigned int *summary,
                                 EmitCoreLane *held, unsigned int atoms, unsigned int places,
                                 unsigned int first, unsigned int last, int cut, unsigned int states,
                                 EmitParts *parts, EmitCoreItem *items)
{
    if (emit_thread() != 0ull)
    {
        return;
    }
    EmitCoreLane lane = *held;
    lane.program = &program;
    const unsigned int order[7] = {EMIT_NOTE,   EMIT_LANE_OPEN, EMIT_DECLARATIONS, EMIT_OPENED,
                                   EMIT_CLOSED, EMIT_BODY_OPEN, EMIT_ENDING};
    for (unsigned int decided = first; decided < last; decided += 1u)
    {
        const unsigned int part = order[decided];
        lane.items = (items != NULL) ? &items[parts->at[part]] : NULL;
        lane.capacity = (items != NULL) ? parts->count[part] : 0ull;
        lane.count = 0ull;
        if (part == EMIT_NOTE)
        {
            emit_core_note(&lane);
        }
        else if (part == EMIT_LANE_OPEN)
        {
            emit_core_form0(&lane, EMIT_FORM_LANE_OPEN);
        }
        else if (part == EMIT_DECLARATIONS)
        {
            emit_core_declare(&lane, atoms);
        }
        else if (part == EMIT_OPENED)
        {
            emit_core_open(&lane, refuses, summary[EMIT_TABLES], places);
        }
        else if (part == EMIT_CLOSED)
        {
            emit_core_close(&lane, refuses);
        }
        else if (part == EMIT_BODY_OPEN)
        {
            emit_core_body_open(&lane, cut, states);
        }
        else
        {
            emit_core_end(&lane);
        }
        if (items == NULL)
        {
            parts->count[part] = lane.count;
        }
    }
    if ((items != NULL) && (first == 0u))
    {
        EmitCoreItem *const header = &items[parts->at[EMIT_HEADER]];
        const EmitCoreArgument none = emit_core_zero();
        header->form = EMIT_TEXT_WHOLE;
        header->count = 0u;
        for (unsigned int at = 0u; at < EMIT_CORE_ARGUMENTS; at += 1u)
        {
            header->arguments[at] = none;
        }
        header->scratch[0] = 0u;
        header->scratch[1] = 0u;
        header->scratch[2] = 0u;
    }
    if (items != NULL)
    {
        summary[EMIT_BROKEN] |= lane.broken;
        lane.program = NULL;
        lane.items = NULL;
        lane.capacity = 0ull;
        lane.count = 0ull;
        *held = lane;
    }
}

// the result of a cut: the forms it took, the states, the most cost one state chains and the forms alone over the budget
struct EmitCutEnd
{
    unsigned long long count;
    unsigned int states;
    unsigned int most;
    unsigned int over;
};

// The body cut into states, in one thread, going on from the lane as `held` holds it: the body's forms, `body_count`
// of them from `body` in the order they run (the opening, the steps and the close), laid into the cut
// (emit_core_cut_item), as the host's lane cuts them. Counted where `items` is NULL; else written there and the lane
// left in `held` for the forms decided after. How it was cut in `ended`
__global__ static void emit_cut(EmitCoreProgram program, unsigned int *summary, EmitCoreLane *held,
                                EmitCoreCut cut, unsigned int writes, unsigned int ports,
                                const EmitCoreItem *body, unsigned long long body_count,
                                unsigned long long capacity, EmitCoreItem *items, EmitCutEnd *ended)
{
    if (emit_thread() != 0ull)
    {
        return;
    }
    EmitCoreLane lane = *held;
    lane.program = &program;
    lane.items = items;
    lane.capacity = (items != NULL) ? capacity : 0ull;
    lane.count = 0ull;
    emit_core_cut_open(&lane, &cut, writes, ports);
    for (unsigned long long at = 0ull; at < body_count; at += 1ull)
    {
        emit_core_cut_item(&lane, &cut, &body[at]);
    }
    emit_core_cut_close(&lane, &cut);
    ended->count = lane.count;
    ended->states = cut.state;
    ended->most = cut.most;
    ended->over = cut.over;
    if (items != NULL)
    {
        summary[EMIT_BROKEN] |= lane.broken;
        lane.program = NULL;
        lane.items = NULL;
        lane.capacity = 0ull;
        lane.count = 0ull;
        *held = lane;
    }
}

// the records each item takes, a thread an item; an item given other arguments than its form takes breaks the lane, as
// the host's writing it does
__global__ static void emit_record_counts(EmitTextLists forms, const EmitCoreItem *items,
                                          unsigned long long item_count, unsigned long long *record_counts,
                                          unsigned int *summary)
{
    const unsigned long long at = emit_thread();
    if (at >= item_count)
    {
        return;
    }
    const int formed = emit_text_formed(&items[at]);
    if (formed == 0)
    {
        atomicOr(&summary[EMIT_BROKEN], 1u);
    }
    record_counts[at] = (formed != 0) ? emit_text_record_count(&forms, &items[at]) : 1ull;
}

// each item's records laid, a thread an item (emit_text_records)
__global__ static void emit_records(EmitTextLists forms, const EmitCoreItem *items,
                                    unsigned long long item_count, const unsigned long long *record_first,
                                    unsigned int *records, unsigned long long *record_lanes)
{
    const unsigned long long at = emit_thread();
    if (at < item_count)
    {
        emit_text_records(&forms, &items[at], record_first[at], records, record_lanes);
    }
}

// each record's first lane laid, and the index that gives each of its lanes the record, a thread a record
__global__ static void emit_index(unsigned int *records, unsigned long long record_count,
                                  const unsigned long long *lane_first, const unsigned long long *record_lanes,
                                  unsigned int *index)
{
    const unsigned long long record = emit_thread();
    if (record >= record_count)
    {
        return;
    }
    emit_text_first(records, record, lane_first[record]);
    for (unsigned long long lane = 0ull; lane < record_lanes[record]; lane += 1ull)
    {
        // a record's number is below 2^31, as the host holds the records
        index[lane_first[record] + lane] = (unsigned int)record;
    }
}

// each lane's byte (emit_text_byte), a thread a lane
__global__ static void emit_bytes(const unsigned int *out, unsigned long long lanes, unsigned int out_limbs,
                                  unsigned int offset, unsigned char *bytes)
{
    const unsigned long long lane = emit_thread();
    if (lane < lanes)
    {
        // a byte, 8 bits
        bytes[lane] = (unsigned char)emit_text_byte(&out[lane * out_limbs], out_limbs, offset);
    }
}

// how keymath's imprint or key_schedule's lay ended on the device: 1 in `held` where it held, else its end and where;
// and, from the lay, the file's limbs and the record's bits
struct EmitLayEnd
{
    int held;
    unsigned int end;
    unsigned int at;
    unsigned long long file_limbs;
    unsigned long long out_bits;
};

// keymath's imprint of the program, in one thread (keymath_core_record_imprint)
__global__ static void emit_imprint(KeymathCoreImprint imprint, EmitLayEnd *ended)
{
    if (emit_thread() != 0ull)
    {
        return;
    }
    ended->held = keymath_core_record_imprint(&imprint);
    ended->end = imprint.end;
    ended->at = imprint.at;
}

// key_schedule's lay of the imprinted program, in one thread (key_schedule_core_record_lay)
__global__ static void emit_lay(KeyScheduleCoreLay lay, EmitLayEnd *ended)
{
    if (emit_thread() != 0ull)
    {
        return;
    }
    ended->held = key_schedule_core_record_lay(&lay);
    ended->end = lay.end;
    ended->at = lay.at;
    ended->file_limbs = lay.file_limbs;
    ended->out_bits = lay.out_bits;
}

// the device memory a lane's writing takes, freed together, and 0 once a call the device refused has left it unusable
struct EmitMemory
{
    std::vector<void *> held;
    int good;
};

template <typename Held>
static Held *emit_take(EmitMemory *memory, unsigned long long count)
{
    void *taken = NULL;
    const unsigned long long bytes = ((count == 0ull) ? 1ull : count) * sizeof(Held);
    if ((memory->good != 0) && (cudaMalloc(&taken, (size_t)bytes) == cudaSuccess))
    {
        memory->held.push_back(taken);
        return (Held *)taken;
    }
    memory->good = 0;
    return NULL;
}

template <typename Held>
static Held *emit_copy(EmitMemory *memory, const Held *from, unsigned long long count)
{
    Held *const to = emit_take<Held>(memory, count);
    if ((memory->good != 0) && (count != 0ull))
    {
        memory->good = cudaMemcpy(to, from, (size_t)(count * sizeof(Held)), cudaMemcpyHostToDevice) == cudaSuccess;
    }
    return to;
}

template <typename Held>
static void emit_read(EmitMemory *memory, Held *to, const Held *from, unsigned long long count)
{
    if ((memory->good != 0) && (count != 0ull))
    {
        memory->good = cudaMemcpy(to, from, (size_t)(count * sizeof(Held)), cudaMemcpyDeviceToHost) == cudaSuccess;
    }
}

static void emit_release(EmitMemory *memory)
{
    for (void *const held : memory->held)
    {
        cudaFree(held);
    }
    memory->held.clear();
}

// the blocks a kernel over `count` threads takes; 0 where the count is past a grid, which the callers hold below
static unsigned int emit_blocks(unsigned long long count)
{
    return (unsigned int)((count + EMIT_THREADS - 1u) / EMIT_THREADS);
}

// a kernel's launch taken; the memory unusable where the device refused it
static void emit_launched(EmitMemory *memory)
{
    memory->good = (memory->good != 0) && (cudaGetLastError() == cudaSuccess);
}

// the exclusive running sum of `count` counts into `sums`, and their total; 0 where there are none
template <typename Counted>
static unsigned long long emit_scan(EmitMemory *memory, const Counted *counts, Counted *sums,
                                    unsigned long long count)
{
    if ((memory->good == 0) || (count == 0ull))
    {
        return 0ull;
    }
    size_t bytes = 0u;
    // held below EMIT_COUNT_MOST by the callers
    memory->good = cub::DeviceScan::ExclusiveSum(NULL, bytes, counts, sums, (int)count) == cudaSuccess;
    void *const temporary = emit_take<unsigned char>(memory, bytes);
    memory->good = (memory->good != 0)
                && (cub::DeviceScan::ExclusiveSum(temporary, bytes, counts, sums, (int)count) == cudaSuccess);
    Counted last_count = 0;
    Counted last_sum = 0;
    emit_read(memory, &last_count, &counts[count - 1ull], 1ull);
    emit_read(memory, &last_sum, &sums[count - 1ull], 1ull);
    return (unsigned long long)last_count + (unsigned long long)last_sum;
}

// the text program laid by the device from what emit_text_ruleset_lay kept of it, into `text_layout`, which the
// caller gives back by key_schedule_record_release: 1 where it is laid and is the host's word for word, else 0 and why
static int emit_text_program_laid(const EmitTextRuleset *text_rules, EngineRecordLayout *text_layout,
                                  std::string *refused)
{
    const EmitTextProgram &kept = text_rules->program;
    const unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX] = {EMIT_TEXT_RECORD_LIMBS, 0u, 0u};
    EmitLayRequest request{};
    request.steps = kept.steps.data();
    // the text program's steps are a few hundred, and its fields and tables a handful
    request.count = (unsigned int)kept.steps.size();
    request.field_bits = kept.field_bits.data();
    request.field_offset = kept.field_offset.data();
    request.fields = (unsigned int)kept.field_bits.size();
    request.members = 1u;
    request.in_limbs = in_limbs;
    request.outputs = &kept.output;
    request.output_count = 1u;
    request.tables = kept.tables.data();
    request.table_count = (unsigned int)kept.tables.size();
    request.reuse = 1;
    std::string why;
    if (emit_lay_device(&request, text_layout, &why) == 0)
    {
        *refused = "the device did not lay the text program (" + why + ")";
        return 0;
    }
    if (emit_lay_same(text_layout, &kept.layout) == 0)
    {
        key_schedule_record_release(text_layout);
        *refused = "the device laid the text program apart from the host's";
        return 0;
    }
    return 1;
}

// `count` items moved from `from` to `to`, both in device memory, apart from each other
static void emit_move(EmitMemory *memory, EmitCoreItem *to, const EmitCoreItem *from,
                      unsigned long long count)
{
    if ((memory->good != 0) && (count != 0ull))
    {
        memory->good = cudaMemcpy(to, from, (size_t)(count * sizeof(EmitCoreItem)), cudaMemcpyDeviceToDevice)
                    == cudaSuccess;
    }
}

// The lane's forms decided on the device, in `held_memory`, which the caller frees, from the step table at
// `device_steps`, in device memory, and the rest of `layout`'s shape, whose own step table is not read, each form's
// construct taking its scratch from `scratch`, `scratch_count` words (emit_ruleset_scratch): in the text's order at
// `*text_items`, `*item_count` of them. Where `cut` is given, the body is cut into states by it and `report` told how,
// as EmitLane::decided cuts it. The forms are decided in three phases, each counted and then written, the lane going
// on from one to the next in device memory: the steps' forms and the lane's own through its close; the cut; the body's
// opening and the end. Every count that sizes the device's memory comes back to the host once: the step forms' total
// and the summary after the steps are counted, each phase's parts after they are counted, and the cut's forms
static int emit_decide(EmitMemory *held_memory, const EngineRecordLayout *layout,
                       const DeviceRecordStep *device_steps, const unsigned int *scratch,
                       unsigned long long scratch_count, unsigned int places, const EmitLaneCut *cut,
                       EmitLaneShaped *report, EmitCoreItem **text_items, unsigned long long *item_count,
                       std::string *refused)
{
    EmitMemory &memory = *held_memory;
    const unsigned int steps = layout->steps;
    if (steps >= EMIT_COUNT_MOST)
    {
        *refused = "the program has more steps than a scan counts";
        return 0;
    }
    if ((cut != NULL) && (cut->cost.size() != EMIT_FORM_COUNT))
    {
        *refused = "the cut does not give each form a cost";
        return 0;
    }
    // the program as every step reads it, in device memory
    EmitCoreProgram program{};
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
    program.steps = device_steps;
    program.scratch = emit_copy(&memory, scratch, scratch_count);
    unsigned int *const put_first = emit_take<unsigned int>(&memory, layout->out_limbs);
    unsigned int *const put_last = emit_take<unsigned int>(&memory, layout->out_limbs);
    unsigned int *const atom_reader = emit_take<unsigned int>(&memory, atoms);
    unsigned int *const loops = emit_take<unsigned int>(&memory, steps);
    unsigned int *const loop_first = emit_take<unsigned int>(&memory, steps);
    unsigned long long *const counts = emit_take<unsigned long long>(&memory, steps);
    unsigned long long *const item_first = emit_take<unsigned long long>(&memory, steps);
    unsigned int *const refuses = emit_take<unsigned int>(&memory, steps);
    unsigned int summary[EMIT_SUMMARY] = {0u};
    // the lane's opening takes %t0 and %w0 before any step does
    summary[EMIT_TEMPS_MOST] = 1u;
    summary[EMIT_WIDES_MOST] = 1u;
    unsigned int *const device_summary = emit_copy(&memory, summary, EMIT_SUMMARY);
    EmitParts parts{};
    EmitParts *const device_parts = emit_copy(&memory, &parts, 1ull);
    EmitCoreLane *const held = emit_take<EmitCoreLane>(&memory, 1ull);
    const size_t out_bytes = sizeof(unsigned int) * layout->out_limbs;
    memory.good = (memory.good != 0) && (cudaMemset(put_first, 0xFF, out_bytes) == cudaSuccess)
               && (cudaMemset(put_last, 0, out_bytes) == cudaSuccess);
    if ((memory.good != 0) && (atoms != 0u))
    {
        emit_fill<<<emit_blocks(atoms), EMIT_THREADS>>>(atom_reader, atoms, steps);
        emit_launched(&memory);
    }
    program.put_first = put_first;
    program.put_last = put_last;
    program.atom_reader = atom_reader;
    if ((memory.good != 0) && (steps != 0u))
    {
        emit_facts<<<emit_blocks(steps), EMIT_THREADS>>>(program, put_first, put_last, atom_reader,
                                                                           loops);
        emit_launched(&memory);
    }
    if ((memory.good != 0) && (layout->out_limbs != 0u))
    {
        emit_unlaid<<<emit_blocks(layout->out_limbs), EMIT_THREADS>>>(put_first, put_last,
                                                                                        layout->out_limbs);
        emit_launched(&memory);
    }
    // the loops every step writes, a loop number each, as the host's lane numbers them in a 32-bit count
    const unsigned int loop_count = (unsigned int)emit_scan(&memory, loops, loop_first, steps);
    // each step's forms counted, and where each step's begin
    if ((memory.good != 0) && (steps != 0u))
    {
        emit_count<<<emit_blocks(steps), EMIT_THREADS>>>(program, loop_first, counts, refuses,
                                                                           device_summary);
        emit_launched(&memory);
    }
    const unsigned long long stepped = emit_scan(&memory, counts, item_first, steps);
    emit_read(&memory, summary, device_summary, EMIT_SUMMARY);
    if ((memory.good != 0) && (summary[EMIT_UNHELD] != 0u))
    {
        *refused = "a step is one the lane does not hold";
        return 0;
    }
    if (memory.good != 0)
    {
        emit_left<<<1u, 1u>>>(device_summary, loop_count, held);
        emit_launched(&memory);
    }
    // phase one: the lane's own forms through its close counted, then laid with the header's item and the steps' forms
    // in the order they are decided, the note, the header, the lane's first form, the declarations, then the body as it
    // runs, its opening, the steps and its close
    if (memory.good != 0)
    {
        emit_tail<<<1u, 1u>>>(program, refuses, device_summary, held, atoms, places, 0u, 5u, 0, 0u, device_parts,
                              NULL);
        emit_launched(&memory);
    }
    emit_read(&memory, &parts, device_parts, 1ull);
    parts.count[EMIT_HEADER] = 1ull;
    parts.count[EMIT_STEPPED] = stepped;
    const unsigned int first_parts[7] = {EMIT_NOTE,         EMIT_HEADER, EMIT_LANE_OPEN,
                                         EMIT_DECLARATIONS, EMIT_OPENED, EMIT_STEPPED,
                                         EMIT_CLOSED};
    unsigned long long first_count = 0ull;
    for (const unsigned int part : first_parts)
    {
        parts.at[part] = first_count;
        first_count += parts.count[part];
    }
    if ((memory.good != 0) && (first_count >= EMIT_COUNT_MOST))
    {
        *refused = "the lane holds more forms than a scan counts";
        return 0;
    }
    memory.good = (memory.good != 0)
               && (cudaMemcpy(device_parts, &parts, sizeof(parts), cudaMemcpyHostToDevice) == cudaSuccess);
    EmitCoreItem *const decided = emit_take<EmitCoreItem>(&memory, first_count);
    if ((memory.good != 0) && (steps != 0u))
    {
        emit_write<<<emit_blocks(steps), EMIT_THREADS>>>(program, loop_first, counts, item_first,
                                                                           &decided[parts.at[EMIT_STEPPED]]);
        emit_launched(&memory);
    }
    if (memory.good != 0)
    {
        emit_tail<<<1u, 1u>>>(program, refuses, device_summary, held, atoms, places, 0u, 5u, 0, 0u, device_parts,
                              decided);
        emit_launched(&memory);
    }
    // the body as it runs, the opening, the steps and the close, one after another
    const EmitCoreItem *const body = &decided[parts.at[EMIT_OPENED]];
    const unsigned long long body_count =
        parts.count[EMIT_OPENED] + parts.count[EMIT_STEPPED] + parts.count[EMIT_CLOSED];
    // phase two: the body cut into states, counted, then written; a refusal's label for the opening and one for each
    // step at most, and each loop the steps wrote
    EmitCoreItem *cut_items = NULL;
    unsigned long long cut_count = 0ull;
    unsigned int states = 0u;
    if (cut != NULL)
    {
        EmitCoreCut laid{};
        laid.cost = emit_copy(&memory, cut->cost.data(), cut->cost.size());
        laid.budget = cut->budget;
        laid.dispatch_refusal = emit_take<EmitCoreArgument>(&memory, (unsigned long long)steps + 1ull);
        laid.dispatch_state = emit_take<unsigned int>(&memory, (unsigned long long)steps + 1ull);
        laid.dispatch_most = steps + 1u;
        laid.loop_state = emit_take<unsigned int>(&memory, (unsigned long long)loop_count + 1ull);
        laid.loop_count = loop_count;
        EmitCutEnd *const device_cut_end = emit_take<EmitCutEnd>(&memory, 1ull);
        EmitCutEnd cut_end{};
        if (memory.good != 0)
        {
            emit_cut<<<1u, 1u>>>(program, device_summary, held, laid, cut->writes, cut->ports, body, body_count,
                                 0ull, NULL, device_cut_end);
            emit_launched(&memory);
        }
        emit_read(&memory, &cut_end, device_cut_end, 1ull);
        cut_count = cut_end.count;
        if ((memory.good != 0) && (cut_count >= EMIT_COUNT_MOST))
        {
            *refused = "the cut lane holds more forms than a scan counts";
            return 0;
        }
        cut_items = emit_take<EmitCoreItem>(&memory, cut_count);
        if (memory.good != 0)
        {
            emit_cut<<<1u, 1u>>>(program, device_summary, held, laid, cut->writes, cut->ports, body, body_count,
                                 cut_count, cut_items, device_cut_end);
            emit_launched(&memory);
        }
        emit_read(&memory, &cut_end, device_cut_end, 1ull);
        states = cut_end.states;
        report->states = cut_end.states;
        report->most = cut_end.most;
        report->over = cut_end.over;
    }
    // phase three: the body's opening and the lane's end, counted, then written
    const int is_cut = (cut != NULL) ? 1 : 0;
    if (memory.good != 0)
    {
        emit_tail<<<1u, 1u>>>(program, refuses, device_summary, held, atoms, places, 5u, 7u, is_cut, states,
                              device_parts, NULL);
        emit_launched(&memory);
    }
    emit_read(&memory, &parts, device_parts, 1ull);
    parts.at[EMIT_BODY_OPEN] = 0ull;
    parts.at[EMIT_ENDING] = parts.count[EMIT_BODY_OPEN];
    const unsigned long long last_count = parts.count[EMIT_BODY_OPEN] + parts.count[EMIT_ENDING];
    memory.good = (memory.good != 0)
               && (cudaMemcpy(device_parts, &parts, sizeof(parts), cudaMemcpyHostToDevice) == cudaSuccess);
    EmitCoreItem *const closing = emit_take<EmitCoreItem>(&memory, last_count);
    if (memory.good != 0)
    {
        emit_tail<<<1u, 1u>>>(program, refuses, device_summary, held, atoms, places, 5u, 7u, is_cut, states,
                              device_parts, closing);
        emit_launched(&memory);
    }
    // the text's order: the note, the header, the lane's first form and the declarations, the body's opening, the body,
    // cut or as it runs, and the end
    const unsigned long long head = parts.count[EMIT_NOTE] + parts.count[EMIT_HEADER]
                                  + parts.count[EMIT_LANE_OPEN] + parts.count[EMIT_DECLARATIONS];
    const unsigned long long body_written = (cut != NULL) ? cut_count : body_count;
    const unsigned long long total = head + last_count + body_written;
    if ((memory.good != 0) && (total >= EMIT_COUNT_MOST))
    {
        *refused = "the lane holds more forms than a scan counts";
        return 0;
    }
    EmitCoreItem *const text = emit_take<EmitCoreItem>(&memory, total);
    emit_move(&memory, text, decided, head);
    emit_move(&memory, &text[head], closing, parts.count[EMIT_BODY_OPEN]);
    emit_move(&memory, &text[head + parts.count[EMIT_BODY_OPEN]], (cut != NULL) ? cut_items : body,
              body_written);
    emit_move(&memory, &text[head + parts.count[EMIT_BODY_OPEN] + body_written],
              &closing[parts.at[EMIT_ENDING]], parts.count[EMIT_ENDING]);
    emit_read(&memory, summary, device_summary, EMIT_SUMMARY);
    if (memory.good == 0)
    {
        *refused = "the device refused a call";
        return 0;
    }
    if (summary[EMIT_BROKEN] != 0u)
    {
        *refused = "a form breaks the lane";
        return 0;
    }
    *text_items = text;
    *item_count = total;
    return 1;
}

// The lane written on the device, in `held_memory`, which the caller frees, from the step table at `device_steps`, in
// device memory, and the rest of `layout`'s shape: its forms decided (emit_decide), cut by `cut` where it is given,
// laid as the text program's records, written a lane a byte and gathered. The records and the lanes come back to the
// host after they are laid, and the text's length after its bytes are gathered
static int emit_written(EmitMemory *held_memory, const EngineRecordLayout *layout,
                        const DeviceRecordStep *device_steps, const EmitTextRuleset *text_rules,
                        unsigned int places, const EmitLaneCut *cut, std::string *text, std::string *refused)
{
    EmitMemory &memory = *held_memory;
    EmitCoreItem *items = NULL;
    unsigned long long item_count = 0ull;
    EmitLaneShaped report{};
    if (emit_decide(held_memory, layout, device_steps, text_rules->scratch.data(), text_rules->scratch.size(),
                    places, cut, &report, &items, &item_count, refused)
        == 0)
    {
        return 0;
    }
    // a form given other arguments than it takes breaks the lane, counted here from none
    unsigned int summary[EMIT_SUMMARY] = {0u};
    unsigned int *const device_summary = emit_copy(&memory, summary, EMIT_SUMMARY);
    // the ruleset's written forms with their lists in device memory, and the records each item takes
    EmitTextLists forms = emit_text_lists(text_rules);
    forms.word_lengths = emit_copy(&memory, text_rules->word_lengths.data(), text_rules->word_lengths.size());
    forms.part_lanes = emit_copy(&memory, text_rules->part_lanes.data(), text_rules->part_lanes.size());
    forms.form_part_first =
        emit_copy(&memory, text_rules->form_part_first.data(), text_rules->form_part_first.size());
    forms.form_parts = emit_copy(&memory, text_rules->form_parts.data(), text_rules->form_parts.size());
    forms.form_slot_first =
        emit_copy(&memory, text_rules->form_slot_first.data(), text_rules->form_slot_first.size());
    forms.slot_parameters =
        emit_copy(&memory, text_rules->slot_parameters.data(), text_rules->slot_parameters.size());
    unsigned long long *const record_counts = emit_take<unsigned long long>(&memory, item_count);
    unsigned long long *const record_first = emit_take<unsigned long long>(&memory, item_count);
    if (memory.good != 0)
    {
        emit_record_counts<<<emit_blocks(item_count), EMIT_THREADS>>>(forms, items, item_count,
                                                                                        record_counts, device_summary);
        emit_launched(&memory);
    }
    const unsigned long long record_count = emit_scan(&memory, record_counts, record_first, item_count);
    emit_read(&memory, summary, device_summary, EMIT_SUMMARY);
    if ((memory.good != 0) && ((summary[EMIT_BROKEN] != 0u) || (record_count >= EMIT_TEXT_LANES_MOST)))
    {
        *refused = (summary[EMIT_BROKEN] != 0u) ? "a form breaks the lane"
                                                      : "the text holds more records than the text program holds";
        return 0;
    }
    unsigned int *const records = emit_take<unsigned int>(&memory, record_count * EMIT_TEXT_RECORD_LIMBS);
    unsigned long long *const record_lanes = emit_take<unsigned long long>(&memory, record_count);
    unsigned long long *const lane_first = emit_take<unsigned long long>(&memory, record_count);
    const size_t record_bytes = sizeof(unsigned int) * EMIT_TEXT_RECORD_LIMBS * (size_t)record_count;
    memory.good = (memory.good != 0) && (cudaMemset(records, 0, record_bytes) == cudaSuccess);
    if (memory.good != 0)
    {
        emit_records<<<emit_blocks(item_count), EMIT_THREADS>>>(forms, items, item_count,
                                                                                  record_first, records, record_lanes);
        emit_launched(&memory);
    }
    const unsigned long long lanes = emit_scan(&memory, record_lanes, lane_first, record_count);
    if ((memory.good != 0) && ((lanes >= EMIT_TEXT_LANES_MOST) || (lanes == 0ull)))
    {
        *refused = "the text holds more lanes than the text program holds";
        return 0;
    }
    unsigned int *const index = emit_take<unsigned int>(&memory, lanes);
    if (memory.good != 0)
    {
        emit_index<<<emit_blocks(record_count), EMIT_THREADS>>>(records, record_count, lane_first,
                                                                                  record_lanes, index);
        emit_launched(&memory);
    }
    if (memory.good == 0)
    {
        *refused = "the device refused a call";
        return 0;
    }
    // the text program laid by the device and held to the host's word for word, then run by the record machine, a
    // lane a byte; its output's offset read before the layout, which the record holds its own of, is given back
    EngineRecordLayout text_layout{};
    if (emit_text_program_laid(text_rules, &text_layout, refused) == 0)
    {
        return 0;
    }
    const unsigned int output_offset = text_layout.step_table[text_rules->program.output].out_offset;
    CycleRecord *record = NULL;
    EngineError error{};
    const long loaded = cycle_record_load(&text_layout, &record, &error);
    key_schedule_record_release(&text_layout);
    if (loaded == CYCLE_REFUSED)
    {
        *refused = "the record machine did not load the text program";
        return 0;
    }
    const unsigned int out_limbs = cycle_record_out_limbs(record);
    unsigned int *const out = emit_take<unsigned int>(&memory, lanes * out_limbs);
    if (memory.good != 0)
    {
        CycleRecordRunRequest request{};
        request.record = record;
        request.device_in[0] = records;
        request.bodies[0] = record_count;
        request.device_index = index;
        request.count = lanes;
        request.device_out = out;
        request.error = &error;
        memory.good = cycle_record_run(&request) != CYCLE_REFUSED;
    }
    cycle_record_release(record);
    // the bytes that are not 0 gathered in lane order
    unsigned char *const bytes = emit_take<unsigned char>(&memory, lanes);
    unsigned char *const gathered = emit_take<unsigned char>(&memory, lanes);
    int *const gathered_count = emit_take<int>(&memory, 1ull);
    if (memory.good != 0)
    {
        emit_bytes<<<emit_blocks(lanes), EMIT_THREADS>>>(out, lanes, out_limbs, output_offset,
                                                                           bytes);
        emit_launched(&memory);
    }
    size_t select_bytes = 0u;
    memory.good = (memory.good != 0)
               && (cub::DeviceSelect::If(NULL, select_bytes, bytes, gathered, gathered_count, (int)lanes,
                                         EmitNonzeroByte()) == cudaSuccess);
    void *const select_temporary = emit_take<unsigned char>(&memory, select_bytes);
    memory.good = (memory.good != 0)
               && (cub::DeviceSelect::If(select_temporary, select_bytes, bytes, gathered, gathered_count, (int)lanes,
                                         EmitNonzeroByte()) == cudaSuccess);
    int length = 0;
    emit_read(&memory, &length, gathered_count, 1ull);
    std::string written((size_t)((length > 0) ? length : 0), '\0');
    emit_read(&memory, &written[0], (const char *)gathered, written.size());
    if (memory.good == 0)
    {
        *refused = "the device refused a call, or the text program did not run";
        return 0;
    }
    *text = written;
    return 1;
}

// why keymath's imprint, where `keymath` is 1, or key_schedule's lay refused the program, from where it ended
static std::string emit_lay_refused(int keymath, const EmitLayEnd *ended)
{
    const std::string at = std::to_string(ended->at);
    if (keymath != 0)
    {
        return (ended->end == KEYMATH_CORE_TABLE)  ? "keymath refused step " + at + "'s table"
             : (ended->end == KEYMATH_CORE_OUTPUT) ? "keymath refused output " + at
                                                   : "keymath refused step " + at;
    }
    return (ended->end == KEY_SCHEDULE_CORE_STEP) ? "key_schedule refused step " + at
         : (ended->end == KEY_SCHEDULE_CORE_FILE) ? "the program's registers are more limbs than the file holds"
                                                  : "the program's outputs are more bits than a record counts";
}

// The program of `request` laid on the device, in `memory`, which the caller frees: keymath's imprint in one thread,
// run again with an arena twice the size while it fills the one it has, then key_schedule's lay in one thread. The step
// table is left in device memory at `*device_steps`, the tables' values, one after another as keymath lays the key's,
// at `*device_values`, `*value_count` words, and the rest of the program's shape laid in `layout`, whose step table and
// tables' values are not. The host checks the request as keymath_record_imprint and key_schedule_record_lay do before
// their cores run, and reads back only how each core ended, the file's limbs and the record's bits
static int emit_lay_steps(EmitMemory *memory, const EmitLayRequest *request, EngineRecordLayout *layout,
                          DeviceRecordStep **device_steps, unsigned int **device_values,
                          unsigned long long *value_count, std::string *refused)
{
    int asked = (request->steps != NULL) && (request->count != 0u) && (request->outputs != NULL)
             && (request->output_count != 0u) && (request->output_count <= request->count)
             && (request->members != 0u) && (request->members <= ENGINE_RECORD_MEMBERS_MAX)
             && (request->in_limbs != NULL) && ((request->tables != NULL) || (request->table_count == 0u));
    for (unsigned int member = 0u; (asked != 0) && (member < request->members); member += 1u)
    {
        asked = request->in_limbs[member] != 0u;
    }
    if (asked == 0)
    {
        *refused = "the request is not a program keymath and key_schedule take";
        return 0;
    }
    if (request->count >= EMIT_COUNT_MOST)
    {
        *refused = "the program has more steps than a scan counts";
        return 0;
    }
    const unsigned int count = request->count;
    // each table's values in device memory, one after another, and its shape pointing at them there; a table indexed
    // by more bits than a table holds, or with no values, is refused whole, as keymath could not lay the key's values
    std::vector<EngineRecordTable> tables(request->table_count);
    std::vector<unsigned long long> table_first(request->table_count);
    std::vector<unsigned long long> table_words(request->table_count);
    unsigned long long words = 0ull;
    for (unsigned int table = 0u; table < request->table_count; table += 1u)
    {
        tables[table] = request->tables[table];
        if ((tables[table].index_bits > ENGINE_RECORD_TABLE_INDEX_BITS_MOST) || (tables[table].values == NULL))
        {
            *refused = "table " + std::to_string(table)
                     + " is indexed by more bits than a table holds, or has no values";
            return 0;
        }
        table_first[table] = words;
        // index_bits is at most 32, and the entry count at most 2^32
        const unsigned long long entries = 1ull << tables[table].index_bits;
        table_words[table] = entries * (unsigned long long)((tables[table].out_bits + 31u) / 32u);
        words += table_words[table];
    }
    unsigned int *const values = emit_take<unsigned int>(memory, words);
    for (unsigned int table = 0u; (memory->good != 0) && (table < request->table_count); table += 1u)
    {
        tables[table].values = &values[table_first[table]];
        if (table_words[table] != 0ull)
        {
            memory->good = cudaMemcpy(&values[table_first[table]], request->tables[table].values,
                                      (size_t)(table_words[table] * sizeof(unsigned int)), cudaMemcpyHostToDevice)
                        == cudaSuccess;
        }
    }
    // the program keymath and key_schedule read, in device memory
    const EngineRecordStep *const steps = emit_copy(memory, request->steps, count);
    const unsigned int *const field_bits =
        (request->field_bits != NULL) ? emit_copy(memory, request->field_bits, request->fields) : NULL;
    const unsigned int *const field_offset =
        (request->field_offset != NULL) ? emit_copy(memory, request->field_offset, request->fields) : NULL;
    const unsigned int *const in_limbs = emit_copy(memory, request->in_limbs, request->members);
    const unsigned int *const outputs = emit_copy(memory, request->outputs, request->output_count);
    const EngineRecordTable *const device_tables =
        (request->tables != NULL) ? emit_copy(memory, tables.data(), request->table_count) : NULL;
    EmitLayEnd *const device_ended = emit_take<EmitLayEnd>(memory, 1ull);
    EmitLayEnd ended{};
    // keymath's imprint: each step's term, never-negative mark and form; an arena that filled stays taken until the
    // memory is freed, and the arenas taken are under twice the last
    EngineRecordTerm *const terms = emit_take<EngineRecordTerm>(memory, count);
    unsigned char *const never_negative = emit_take<unsigned char>(memory, count);
    memory->good = (memory->good != 0) && (cudaMemset(never_negative, 0, count) == cudaSuccess);
    KeymathCoreImprint imprint{};
    imprint.steps = steps;
    imprint.count = count;
    imprint.field_bits = field_bits;
    imprint.fields = request->fields;
    imprint.members = request->members;
    imprint.outputs = outputs;
    imprint.output_count = request->output_count;
    imprint.tables = device_tables;
    imprint.table_count = request->table_count;
    imprint.terms = terms;
    imprint.never_negative = never_negative;
    imprint.forms = emit_take<KeymathCoreForm>(memory, count);
    imprint.bound = emit_take<unsigned int>(memory, KEYMATH_BOUND_LIMBS);
    unsigned long long capacity = (unsigned long long)count * KEYMATH_ARENA_PER_STEP;
    do
    {
        imprint.arena.terms = emit_take<KeymathCoreTerm>(memory, capacity);
        imprint.arena.capacity = capacity;
        if (memory->good != 0)
        {
            emit_imprint<<<1u, 1u>>>(imprint, device_ended);
            emit_launched(memory);
        }
        emit_read(memory, &ended, device_ended, 1ull);
        capacity *= 2ull;
    } while ((memory->good != 0) && (ended.held == 0) && (ended.end == KEYMATH_CORE_FULL));
    if ((memory->good != 0) && (ended.held == 0))
    {
        *refused = emit_lay_refused(1, &ended);
        return 0;
    }
    // key_schedule's lay: each step laid for the device and placed, and each output placed in the record
    DeviceRecordStep *const laid = emit_take<DeviceRecordStep>(memory, count);
    KeyScheduleCoreLay lay{};
    lay.terms = terms;
    lay.step_count = count;
    lay.outputs = outputs;
    lay.output_count = request->output_count;
    lay.tables = device_tables;
    lay.table_count = request->table_count;
    lay.field_offset = field_offset;
    lay.fields = request->fields;
    lay.in_limbs = in_limbs;
    lay.reuse = request->reuse;
    lay.steps = laid;
    lay.last_use = emit_take<unsigned int>(memory, count);
    lay.ending_first = emit_take<unsigned int>(memory, (unsigned long long)count + 1ull);
    lay.ending = emit_take<unsigned int>(memory, count);
    lay.freed = emit_take<KeyScheduleBlock>(memory, (unsigned long long)count + 1ull);
    lay.table_offset = emit_take<unsigned long long>(memory, (unsigned long long)request->table_count + 1ull);
    ended = EmitLayEnd{};
    if (memory->good != 0)
    {
        emit_lay<<<1u, 1u>>>(lay, device_ended);
        emit_launched(memory);
    }
    emit_read(memory, &ended, device_ended, 1ull);
    if (memory->good == 0)
    {
        *refused = "the device refused a call";
        return 0;
    }
    if (ended.held == 0)
    {
        *refused = emit_lay_refused(0, &ended);
        return 0;
    }
    // the shape as key_schedule_record_lay lays it; the lay held the file to ENGINE_RECORD_LIMBS_MOST limbs and the
    // record's bits to a 31-bit count
    memset(layout, 0, sizeof(*layout));
    layout->steps = count;
    layout->members = request->members;
    layout->file_limbs = (unsigned int)ended.file_limbs;
    for (unsigned int member = 0u; member < request->members; member += 1u)
    {
        layout->in_limbs[member] = request->in_limbs[member];
    }
    layout->out_bits = (unsigned int)ended.out_bits;
    layout->out_limbs = (unsigned int)((ended.out_bits + 31ull) / 32ull);
    *device_steps = laid;
    *device_values = values;
    *value_count = words;
    return 1;
}

int emit_device(const EngineRecordLayout *layout, const EmitTextRuleset *text_rules, unsigned int places,
                const EmitLaneCut *cut, std::string *text, std::string *refused)
{
    EmitMemory memory = {std::vector<void *>(), 1};
    const DeviceRecordStep *const device_steps = emit_copy(&memory, layout->step_table, layout->steps);
    const int written = emit_written(&memory, layout, device_steps, text_rules, places, cut, text, refused);
    emit_release(&memory);
    return written;
}

int emit_lay_device(const EmitLayRequest *request, EngineRecordLayout *layout, std::string *refused)
{
    EmitMemory memory = {std::vector<void *>(), 1};
    DeviceRecordStep *device_steps = NULL;
    unsigned int *device_values = NULL;
    unsigned long long value_count = 0ull;
    EngineRecordLayout laid{};
    int held = emit_lay_steps(&memory, request, &laid, &device_steps, &device_values, &value_count, refused);
    // the step table and the tables' values read back, laid as key_schedule_record_lay lays them
    if (held != 0)
    {
        laid.step_table = (DeviceRecordStep *)malloc((size_t)laid.steps * sizeof(DeviceRecordStep));
        laid.table_values =
            (value_count != 0ull) ? (unsigned int *)malloc((size_t)(value_count + 1ull) * sizeof(unsigned int)) : NULL;
        laid.table_word_count = value_count;
        held = (laid.step_table != NULL) && ((value_count == 0ull) || (laid.table_values != NULL));
        if (held != 0)
        {
            emit_read(&memory, laid.step_table, device_steps, laid.steps);
            emit_read(&memory, laid.table_values, device_values, value_count);
            held = memory.good != 0;
        }
        if (held == 0)
        {
            *refused =
                (memory.good != 0) ? "the host could not hold the layout read back" : "the device refused a call";
            free(laid.step_table);
            free(laid.table_values);
            laid = EngineRecordLayout{};
        }
    }
    emit_release(&memory);
    *layout = laid;
    return held;
}

int emit_device_steps(const EmitLayRequest *request, const EmitTextRuleset *text_rules, unsigned int places,
                      const EmitLaneCut *cut, std::string *text, std::string *refused)
{
    EmitMemory memory = {std::vector<void *>(), 1};
    DeviceRecordStep *device_steps = NULL;
    unsigned int *device_values = NULL;
    unsigned long long value_count = 0ull;
    EngineRecordLayout laid{};
    const int written =
        (emit_lay_steps(&memory, request, &laid, &device_steps, &device_values, &value_count, refused) != 0)
        && (emit_written(&memory, &laid, device_steps, text_rules, places, cut, text, refused) != 0);
    emit_release(&memory);
    return written;
}

int emit_device_items(const EngineRecordLayout *layout, const std::vector<unsigned int> &scratch,
                      unsigned int places, const EmitLaneCut *cut, EmitLaneShaped *report,
                      std::vector<EmitCoreItem> *items, std::string *refused)
{
    EmitMemory memory = {std::vector<void *>(), 1};
    const DeviceRecordStep *const device_steps = emit_copy(&memory, layout->step_table, layout->steps);
    EmitCoreItem *decided = NULL;
    unsigned long long item_count = 0ull;
    int held = emit_decide(&memory, layout, device_steps, scratch.data(), scratch.size(), places, cut, report,
                           &decided, &item_count, refused);
    if (held != 0)
    {
        items->assign((size_t)item_count, EmitCoreItem{});
        emit_read(&memory, items->data(), decided, item_count);
        held = memory.good != 0;
        *refused = (held != 0) ? *refused : std::string("the device refused a call");
    }
    emit_release(&memory);
    return held;
}
#else
int emit_device(const EngineRecordLayout *layout, const EmitTextRuleset *text_rules, unsigned int places,
                const EmitLaneCut *cut, std::string *text, std::string *refused)
{
    (void)layout;
    (void)text_rules;
    (void)places;
    (void)cut;
    (void)text;
    *refused = "the build has no device";
    return 0;
}

int emit_lay_device(const EmitLayRequest *request, EngineRecordLayout *layout, std::string *refused)
{
    (void)request;
    (void)layout;
    *refused = "the build has no device";
    return 0;
}

int emit_device_steps(const EmitLayRequest *request, const EmitTextRuleset *text_rules, unsigned int places,
                      const EmitLaneCut *cut, std::string *text, std::string *refused)
{
    (void)request;
    (void)text_rules;
    (void)places;
    (void)cut;
    (void)text;
    *refused = "the build has no device";
    return 0;
}

int emit_device_items(const EngineRecordLayout *layout, const std::vector<unsigned int> &scratch,
                      unsigned int places, const EmitLaneCut *cut, EmitLaneShaped *report,
                      std::vector<EmitCoreItem> *items, std::string *refused)
{
    (void)layout;
    (void)scratch;
    (void)places;
    (void)cut;
    (void)report;
    (void)items;
    *refused = "the build has no device";
    return 0;
}
#endif
