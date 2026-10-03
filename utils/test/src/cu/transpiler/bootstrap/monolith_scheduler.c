// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// monolith_scheduler.c: the scheduler's bits NVIDIA's compiler writes, read off its cubins and gathered by operation.
// No listing is read and no disassembler is run: each cubin's code sections are read from the ELF, each instruction is
// named by our reader through the machine file, and its bits 105 to 127 are read through the fields the machine file
// names (sass_machine.h).
//
//     monolith_scheduler <machine file> <record> <cubin>...
//
// For each operation the record holds how often NVIDIA wrote it, the stalls it gave it, how often it set a write or a
// read barrier and how often it waited, and two readings of what the scheduler's bits are for:
//
// - where the operation sets no write barrier, the fewest cycles NVIDIA leaves between it and the first instruction
//   that reads the register it writes, the stalls between them summed. That count is the soonest NVIDIA lets the result
//   be read, and holds for the operation wherever it is written
// - where the operation sets a write barrier, how often a wait on that barrier stands between it and the first
//   instruction that reads its register, against how often none does. A barrier counts its producers, and a wait on it
//   holds until every one of them is back: the wait may stand at the reader or at any instruction before it
// - where the operation sets none and a later instruction of the same operation sets one, waited on before the read:
//   the earlier result is held behind the later one's barrier, the two coming back in the order they were put
// - where the operation sets none, no later one holds it, and an earlier instruction of the same operation sets one,
//   waited on before the read: the result follows the earlier one's out of the same unit, and the fewest cycles NVIDIA
//   leaves between that wait and the read
//
// and whether the machine file's form for the operation records the barrier NVIDIA writes.
#include "../../../../../../src/c/transpiler/cubin/sass_assemble.h"

#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// the most bytes a cubin takes, the most instructions a section holds, the most operations kept apart, the most
// registers an instruction reads, and the farthest a reader is looked for past the instruction it reads from
#define SCHEDULER_CUBIN_BYTES 4194304u
#define SCHEDULER_SECTION_INSTRUCTIONS 65536u
#define SCHEDULER_OPERATIONS 2048u
#define SCHEDULER_READS 16u
#define SCHEDULER_REACH 32u
// a register number no instruction names, for an instruction that writes none
#define SCHEDULER_NO_REGISTER 0xffffffffu

// one instruction of a section, its scheduler's fields read apart and the registers it writes and reads
typedef struct
{
    unsigned int operation;
    unsigned int stall;
    unsigned int write_barrier;
    unsigned int read_barrier;
    unsigned int wait;
    unsigned int control;
    unsigned int writes;
    unsigned int reads;
    unsigned int read[SCHEDULER_READS];
} SchedulerInstruction;

// one operation as NVIDIA wrote it, everything gathered over every place it was written
typedef struct
{
    char name[SASS_MACHINE_TOKEN];
    unsigned long long count;
    unsigned long long stalls[16];
    unsigned long long yields;
    unsigned long long write_barriers;
    unsigned long long read_barriers;
    unsigned long long waits;
    unsigned int soonest_read;
    unsigned long long timed_reads;
    unsigned long long readers_waiting;
    unsigned long long readers_not_waiting;
    unsigned long long readers_behind_later;
    unsigned long long readers_behind_earlier;
    unsigned int soonest_after_earlier;
    unsigned long long machine_barriers;
    unsigned long long machine_read_barriers;
    unsigned long long machine_formed;
} SchedulerOperation;

static SassMachine s_machine;
static unsigned char s_cubin[SCHEDULER_CUBIN_BYTES];
static SchedulerInstruction s_section[SCHEDULER_SECTION_INSTRUCTIONS];
static SchedulerOperation s_operation[SCHEDULER_OPERATIONS];
static unsigned int s_operations;
static unsigned long long s_instructions;
static unsigned long long s_unread;
static unsigned int s_cubins;

static unsigned long long scheduler_word(const unsigned char *bytes, unsigned int width)
{
    unsigned long long word = 0ull;
    for (unsigned int at = 0u; at < width; at += 1u)
    {
        word |= (unsigned long long)bytes[at] << (8u * at);
    }
    return word;
}

// the scheduler's field beginning at `first`, `bits` wide, of the high word `high`
static unsigned int scheduler_field(unsigned long long high, unsigned int first, unsigned int bits)
{
    return (unsigned int)((high >> (first - 64u)) & ((1ull << bits) - 1ull));
}

// the operation named `name`, kept in s_operation where it is not yet: its number, or SCHEDULER_OPERATIONS where the
// table is full
static unsigned int scheduler_operation(const char *name)
{
    for (unsigned int at = 0u; at < s_operations; at += 1u)
    {
        if (strcmp(s_operation[at].name, name) == 0)
        {
            return at;
        }
    }
    if (s_operations == SCHEDULER_OPERATIONS)
    {
        return SCHEDULER_OPERATIONS;
    }
    SchedulerOperation *const made = &s_operation[s_operations];
    memset(made, 0, sizeof(*made));
    snprintf(made->name, sizeof(made->name), "%s", name);
    made->soonest_read = UINT_MAX;
    made->soonest_after_earlier = UINT_MAX;
    s_operations += 1u;
    return s_operations - 1u;
}

// 1 where the operation writes predicates alone: a compare that sets them and the logic over them, whose register
// operands are each read
static int scheduler_predicates_only(const char *operation)
{
    static const char *const setters[] = {"ISETP", "FSETP", "DSETP", "HSETP2", "PSETP", "PLOP3", "UISETP", "UPLOP3"};
    for (unsigned int at = 0u; at < (sizeof(setters) / sizeof(setters[0])); at += 1u)
    {
        if (strncmp(operation, setters[at], strlen(setters[at])) == 0)
        {
            return 1;
        }
    }
    return 0;
}

// 1 where the operation leaves the straight line: a branch, a call, a return, an exit or a wait on other lanes, past
// which a reader is not looked for
static int scheduler_control(const char *operation)
{
    static const char *const leaves[] = {"BRA", "BRX", "JMP", "JMX", "CALL", "RET", "EXIT", "BSSY", "BSYNC", "BREAK",
                                         "WARPSYNC", "BAR", "KILL", "BPT", "YIELD", "NANOSLEEP"};
    for (unsigned int at = 0u; at < (sizeof(leaves) / sizeof(leaves[0])); at += 1u)
    {
        if (strncmp(operation, leaves[at], strlen(leaves[at])) == 0)
        {
            return 1;
        }
    }
    return 0;
}

// every register `text` names, R then digits, added to the instruction's reads; a register named with .64 adds the
// one after it too, the second of its pair
static void scheduler_reads(const char *text, SchedulerInstruction *instruction)
{
    for (const char *walk = text; *walk != '\0'; walk += 1)
    {
        const int starts = (walk[0] == 'R') && (walk[1] >= '0') && (walk[1] <= '9') &&
                           ((walk == text) || ((walk[-1] != 'U') && (walk[-1] != 'S')));
        if (!starts)
        {
            continue;
        }
        char *after = NULL;
        const unsigned long number = strtoul(walk + 1, &after, 10);
        const unsigned int pair = (strncmp(after, ".64", 3u) == 0) ? 2u : 1u;
        for (unsigned int add = 0u; (add < pair) && (instruction->reads < SCHEDULER_READS); add += 1u)
        {
            instruction->read[instruction->reads] = (unsigned int)number + add;
            instruction->reads += 1u;
        }
    }
}

// 1 where `instruction` reads register `number`
static int scheduler_reads_register(const SchedulerInstruction *instruction, unsigned int number)
{
    for (unsigned int at = 0u; at < instruction->reads; at += 1u)
    {
        if (instruction->read[at] == number)
        {
            return 1;
        }
    }
    return 0;
}

// the instruction at `bytes` read into `instruction` and counted against its operation
static void scheduler_instruction(const unsigned char *bytes, unsigned long long address,
                                  SchedulerInstruction *instruction)
{
    const unsigned long long low = scheduler_word(bytes, 8u);
    const unsigned long long high = scheduler_word(&bytes[8], 8u);
    memset(instruction, 0, sizeof(*instruction));
    instruction->stall = scheduler_field(high, SASS_STALL_FIRST, 4u);
    instruction->write_barrier = scheduler_field(high, SASS_WRITE_BARRIER_FIRST, 3u);
    instruction->read_barrier = scheduler_field(high, SASS_READ_BARRIER_FIRST, 3u);
    instruction->wait = scheduler_field(high, SASS_WAIT_FIRST, 6u);
    instruction->writes = SCHEDULER_NO_REGISTER;
    instruction->control = 1u;
    char text[256];
    char name[SASS_MACHINE_TOKEN];
    SassInstructionParts parts;
    const int read = sass_encoding_read(&s_machine, low, high, address, text, sizeof(text));
    if (read)
    {
        sass_instruction_read(text, &parts);
        snprintf(name, sizeof(name), "%s", parts.operation);
    }
    else
    {
        snprintf(name, sizeof(name), "no form, key 0x%03llx", low & 0xfffull);
        s_unread += 1ull;
    }
    s_instructions += 1ull;
    instruction->operation = scheduler_operation(name);
    if (instruction->operation == SCHEDULER_OPERATIONS)
    {
        return;
    }
    SchedulerOperation *const operation = &s_operation[instruction->operation];
    operation->count += 1ull;
    operation->stalls[instruction->stall] += 1ull;
    operation->yields += (unsigned long long)scheduler_field(high, SASS_YIELD_FIRST, 1u);
    operation->write_barriers += (instruction->write_barrier != SASS_BARRIER_NONE) ? 1ull : 0ull;
    operation->read_barriers += (instruction->read_barrier != SASS_BARRIER_NONE) ? 1ull : 0ull;
    operation->waits += (instruction->wait != 0u) ? 1ull : 0ull;
    if (!read)
    {
        return;
    }
    const SassForm *const form = sass_machine_form(&s_machine, &parts);
    if (form != NULL)
    {
        operation->machine_formed += 1ull;
        operation->machine_barriers += sass_barrier_set(form->high, SASS_WRITE_BARRIER_FIRST) ? 1ull : 0ull;
        operation->machine_read_barriers += sass_barrier_set(form->high, SASS_READ_BARRIER_FIRST) ? 1ull : 0ull;
    }
    instruction->control = (unsigned int)scheduler_control(parts.operation);
    // the outputs lead: any predicates first, then the register written, where the operation writes one. A compare or
    // a logic over predicates writes predicates alone, and an operation that leaves the straight line reads its
    // register
    unsigned int written = 0u;
    while ((written < parts.operands) && (parts.kind[written] == SASS_OPERAND_PREDICATE))
    {
        written += 1u;
    }
    const int writes_register = (written < parts.operands) && (parts.kind[written] == SASS_OPERAND_REGISTER) &&
                                !instruction->control && !scheduler_predicates_only(parts.operation);
    if (writes_register && (strcmp(parts.operand[written], "RZ") != 0))
    {
        instruction->writes = (unsigned int)strtoul(parts.operand[written] + 1, NULL, 10);
    }
    for (unsigned int at = writes_register ? (written + 1u) : 0u; at < parts.operands; at += 1u)
    {
        scheduler_reads(parts.operand[at], instruction);
    }
}

// 1 where an instruction of the section from `first` to `last` waits on barrier `barrier`
static int scheduler_waited(unsigned int barrier, unsigned int first, unsigned int last)
{
    for (unsigned int at = first; at <= last; at += 1u)
    {
        if ((s_section[at].wait >> barrier) & 1u)
        {
            return 1;
        }
    }
    return 0;
}

// 1 where operations `one` and `two` share their names before the first dot
static int scheduler_same_operation(unsigned int one, unsigned int two)
{
    const char *const left = s_operation[one].name;
    const char *const right = s_operation[two].name;
    const size_t length = strcspn(left, ".");
    return (length == strcspn(right, ".")) && (strncmp(left, right, length) == 0);
}

// 1 where an instruction after `writer` and before `reader`, of the writer's operation, sets a write barrier that an
// instruction after it and no later than the reader waits on
static int scheduler_behind_later(unsigned int writer, unsigned int reader)
{
    for (unsigned int at = writer + 1u; at < reader; at += 1u)
    {
        const SchedulerInstruction *const later = &s_section[at];
        if ((later->operation != SCHEDULER_OPERATIONS) && (later->write_barrier != SASS_BARRIER_NONE) &&
            scheduler_same_operation(s_section[writer].operation, later->operation) &&
            scheduler_waited(later->write_barrier, at + 1u, reader))
        {
            return 1;
        }
    }
    return 0;
}

// where an instruction before `writer`, of the writer's operation and no farther back than SCHEDULER_REACH, sets a
// write barrier that an instruction after the writer and no later than `reader` waits on: the cycles between the first
// such wait and the reader, or UINT_MAX where there is none
static unsigned int scheduler_behind_earlier(unsigned int writer, unsigned int reader)
{
    const unsigned int reach = (writer > SCHEDULER_REACH) ? (writer - SCHEDULER_REACH) : 0u;
    for (unsigned int back = writer; back > reach; back -= 1u)
    {
        const SchedulerInstruction *const earlier = &s_section[back - 1u];
        if ((earlier->operation == SCHEDULER_OPERATIONS) || (earlier->write_barrier == SASS_BARRIER_NONE) ||
            !scheduler_same_operation(s_section[writer].operation, earlier->operation))
        {
            continue;
        }
        for (unsigned int at = writer + 1u; at <= reader; at += 1u)
        {
            if ((s_section[at].wait >> earlier->write_barrier) & 1u)
            {
                unsigned int cycles = 0u;
                for (unsigned int step = at; step < reader; step += 1u)
                {
                    cycles += s_section[step].stall;
                }
                return cycles;
            }
        }
    }
    return UINT_MAX;
}

// each instruction of a section that writes a register, followed to the first instruction that reads it: where the
// writer sets a write barrier, whether a wait on it stands between them; where it sets none, whether it is held behind
// a later one's barrier, and otherwise the cycles between them. The look stops at an instruction that leaves the
// straight line, one that writes the register again, and past SCHEDULER_REACH instructions
static void scheduler_follow(unsigned int count)
{
    for (unsigned int at = 0u; at < count; at += 1u)
    {
        const SchedulerInstruction *const writer = &s_section[at];
        if ((writer->writes == SCHEDULER_NO_REGISTER) || (writer->operation == SCHEDULER_OPERATIONS))
        {
            continue;
        }
        SchedulerOperation *const operation = &s_operation[writer->operation];
        unsigned int cycles = 0u;
        for (unsigned int next = at + 1u; (next < count) && (next <= at + SCHEDULER_REACH); next += 1u)
        {
            cycles += s_section[next - 1u].stall;
            const SchedulerInstruction *const reader = &s_section[next];
            if (scheduler_reads_register(reader, writer->writes))
            {
                if (writer->write_barrier != SASS_BARRIER_NONE)
                {
                    const int waited = scheduler_waited(writer->write_barrier, at + 1u, next);
                    operation->readers_waiting += waited ? 1ull : 0ull;
                    operation->readers_not_waiting += waited ? 0ull : 1ull;
                }
                else if (scheduler_behind_later(at, next))
                {
                    operation->readers_behind_later += 1ull;
                }
                else if (scheduler_behind_earlier(at, next) != UINT_MAX)
                {
                    const unsigned int after = scheduler_behind_earlier(at, next);
                    operation->readers_behind_earlier += 1ull;
                    operation->soonest_after_earlier =
                        (after < operation->soonest_after_earlier) ? after : operation->soonest_after_earlier;
                }
                else
                {
                    operation->timed_reads += 1ull;
                    operation->soonest_read = (cycles < operation->soonest_read) ? cycles : operation->soonest_read;
                }
                break;
            }
            if (reader->control || (reader->writes == writer->writes))
            {
                break;
            }
        }
    }
}

// every code section of the ELF in s_cubin, `size` bytes, read and followed. 1, or 0 where it is not an ELF this
// reads
static int scheduler_cubin(unsigned long long size)
{
    if ((size < 0x40ull) || (memcmp(s_cubin, "\x7f" "ELF", 4u) != 0))
    {
        return 0;
    }
    const unsigned long long table = scheduler_word(&s_cubin[0x28], 8u);
    const unsigned int entry = (unsigned int)scheduler_word(&s_cubin[0x3a], 2u);
    const unsigned int count = (unsigned int)scheduler_word(&s_cubin[0x3c], 2u);
    const unsigned int names = (unsigned int)scheduler_word(&s_cubin[0x3e], 2u);
    if ((names >= count) || ((table + ((unsigned long long)entry * count)) > size))
    {
        return 0;
    }
    const unsigned long long strings = scheduler_word(&s_cubin[table + ((unsigned long long)entry * names) + 0x18], 8u);
    for (unsigned int section = 0u; section < count; section += 1u)
    {
        const unsigned char *const header = &s_cubin[table + ((unsigned long long)entry * section)];
        const unsigned long long label = strings + scheduler_word(header, 4u);
        const unsigned long long offset = scheduler_word(&header[0x18], 8u);
        const unsigned long long length = scheduler_word(&header[0x20], 8u);
        if ((label >= size) || (strncmp((const char *)&s_cubin[label], ".text.", 6u) != 0) ||
            ((offset + length) > size))
        {
            continue;
        }
        const unsigned int instructions = (unsigned int)(length / 16ull);
        const unsigned int kept =
            (instructions < SCHEDULER_SECTION_INSTRUCTIONS) ? instructions : SCHEDULER_SECTION_INSTRUCTIONS;
        for (unsigned int at = 0u; at < kept; at += 1u)
        {
            scheduler_instruction(&s_cubin[offset + (16ull * at)], 16ull * at, &s_section[at]);
        }
        scheduler_follow(kept);
    }
    return 1;
}

// the stalls an operation was given, as the least, the most and the one given most often
static void scheduler_stalls(const SchedulerOperation *operation, char *text, size_t room)
{
    unsigned int least = 16u;
    unsigned int most = 0u;
    unsigned int often = 0u;
    for (unsigned int stall = 0u; stall < 16u; stall += 1u)
    {
        if (operation->stalls[stall] == 0ull)
        {
            continue;
        }
        least = (stall < least) ? stall : least;
        most = stall;
        often = (operation->stalls[stall] > operation->stalls[often]) ? stall : often;
    }
    snprintf(text, room, "%u to %u, most often %u", least, most, often);
}

static int scheduler_by_count(const void *left, const void *right)
{
    const SchedulerOperation *const one = (const SchedulerOperation *)left;
    const SchedulerOperation *const two = (const SchedulerOperation *)right;
    return (one->count < two->count) ? 1 : ((one->count > two->count) ? -1 : strcmp(one->name, two->name));
}

// the record: every operation by how often NVIDIA wrote it, and the readings gathered from them
static int scheduler_record(const char *path)
{
    FILE *const out = fopen(path, "wb");
    if (out == NULL)
    {
        return 0;
    }
    qsort(s_operation, s_operations, sizeof(s_operation[0]), scheduler_by_count);
    fprintf(out, "# The scheduler's bits NVIDIA's compiler writes\n\n");
    fprintf(out, "Written by `monolith_scheduler.sh` whole on every run. Every CUDA source of the tree is built by "
                 "NVIDIA's compiler for one part, each cubin's code sections are read from the ELF, each instruction "
                 "is named by our reader through the machine file and its bits 105 to 127 read through the fields the "
                 "machine file names. No listing is read and no disassembler is run.\n\n");
    fprintf(out, "%u cubins, %llu instructions, %llu no form reads, %u operations.\n\n", s_cubins, s_instructions,
            s_unread, s_operations);
    fprintf(out, "An operation's soonest read is the fewest cycles, its stalls summed, between it and the first "
                 "instruction that reads the register it writes, over every place it sets no write barrier and no "
                 "later one holds it. Readers waiting count the first readers of a register it writes with a write "
                 "barrier where a wait on that barrier stands between the two, at the reader or before it, against "
                 "those where none does. A barrier counts its producers, and a wait on it holds until all of them are "
                 "back. Behind a later one counts the first readers of a register it writes with no barrier where a "
                 "later instruction of the same operation sets one, waited on before the read. Behind an earlier one "
                 "counts those where no later one does and an earlier instruction of the same operation sets one, "
                 "waited on before the read, with the fewest cycles between that wait and the read. The machine file "
                 "columns count the places whose form records a write barrier, and a read barrier, against the places "
                 "a form was found.\n\n");
    fprintf(out, "| operation | written | stalls | write barrier | read barrier | waits | soonest read | readers "
                 "waiting | behind a later one | behind an earlier one | machine file write | machine file read |\n"
                 "|---|---|---|---|---|---|---|---|---|---|---|---|\n");
    for (unsigned int at = 0u; at < s_operations; at += 1u)
    {
        const SchedulerOperation *const operation = &s_operation[at];
        char stalls[64];
        char soonest[64];
        scheduler_stalls(operation, stalls, sizeof(stalls));
        if (operation->timed_reads == 0ull)
        {
            snprintf(soonest, sizeof(soonest), "-");
        }
        else
        {
            snprintf(soonest, sizeof(soonest), "%u over %llu", operation->soonest_read, operation->timed_reads);
        }
        char earlier[64];
        if (operation->readers_behind_earlier == 0ull)
        {
            snprintf(earlier, sizeof(earlier), "0");
        }
        else
        {
            snprintf(earlier, sizeof(earlier), "%llu, %u after the wait", operation->readers_behind_earlier,
                     operation->soonest_after_earlier);
        }
        fprintf(out,
                "| `%s` | %llu | %s | %llu | %llu | %llu | %s | %llu of %llu | %llu | %s | %llu of %llu | %llu of %llu |\n",
                operation->name, operation->count, stalls, operation->write_barriers, operation->read_barriers,
                operation->waits, soonest, operation->readers_waiting,
                operation->readers_waiting + operation->readers_not_waiting, operation->readers_behind_later, earlier,
                operation->machine_barriers, operation->machine_formed, operation->machine_read_barriers,
                operation->machine_formed);
    }
    fclose(out);
    return 1;
}

int main(int count, char **words)
{
    if ((count < 4) || !sass_machine_read(&s_machine, words[1]))
    {
        fprintf(stderr, "monolith_scheduler <machine file> <record> <cubin>...\n");
        return 2;
    }
    for (int at = 3; at < count; at += 1)
    {
        FILE *const file = fopen(words[at], "rb");
        if (file == NULL)
        {
            continue;
        }
        const size_t size = fread(s_cubin, 1u, sizeof(s_cubin), file);
        fclose(file);
        s_cubins += ((size < sizeof(s_cubin)) && scheduler_cubin(size)) ? 1u : 0u;
    }
    if (!scheduler_record(words[2]))
    {
        fprintf(stderr, "the record %s was not written\n", words[2]);
        return 2;
    }
    printf("monolith scheduler: %u cubins, %llu instructions, %llu no form reads, %u operations\n", s_cubins,
           s_instructions, s_unread, s_operations);
    return 0;
}
