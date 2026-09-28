// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// codegen_device_reader.cu: a ruleset's .krs file read, and its scratch laid out, on the device, and held to the host's
#include "codegen_device.h"
#include "codegen_device_internal.h"
#include "ruleset_flat.h"

// 1 where two templates are the same: their pieces and slots
static int ruleset_same_templates(const std::vector<InstrTemplate> &left, const std::vector<InstrTemplate> &right)
{
    int same = left.size() == right.size();
    for (size_t at = 0u; (same != 0) && (at < left.size()); at += 1u)
    {
        same = (left[at].pieces == right[at].pieces) && (left[at].slots == right[at].slots);
    }
    return same;
}

// 1 where two rulesets' constructs are the same: each line's form and each argument's kind, slot, number and text
static int ruleset_same_constructs(const std::vector<Pseudo> &left, const std::vector<Pseudo> &right)
{
    int same = left.size() == right.size();
    for (size_t construct = 0u; (same != 0) && (construct < left.size()); construct += 1u)
    {
        const std::vector<PseudoLine> &one = left[construct].lines;
        const std::vector<PseudoLine> &other = right[construct].lines;
        same = one.size() == other.size();
        for (size_t line = 0u; (same != 0) && (line < one.size()); line += 1u)
        {
            same = (one[line].form == other[line].form) && (one[line].arguments.size() == other[line].arguments.size());
            for (size_t at = 0u; (same != 0) && (at < one[line].arguments.size()); at += 1u)
            {
                const PseudoOperand &given = one[line].arguments[at];
                const PseudoOperand &taken = other[line].arguments[at];
                same = (given.kind == taken.kind) && (given.slot == taken.slot) && (given.number == taken.number) &&
                       (given.text == taken.text);
            }
        }
    }
    return same;
}

int ruleset_same(const Ruleset *left, const Ruleset *right)
{
    return (left->schema == right->schema) && (left->path == right->path) && (left->error == right->error) &&
           (left->name == right->name) && (left->toolchain == right->toolchain) && (left->header == right->header) &&
           ruleset_same_templates(left->banks, right->banks) && (left->fixed == right->fixed) &&
           ruleset_same_templates(left->forms, right->forms) &&
           ruleset_same_constructs(left->constructs, right->constructs) && (left->bank_given == right->bank_given) &&
           (left->fixed_given == right->fixed_given) && (left->form_given == right->form_given) &&
           (left->building == right->building) && (left->building_parameters == right->building_parameters);
}

#if (defined(__CUDACC__))

// the read in one thread (ruleset_core_read), since each line is read against every line before it; the read held in
// device memory and left there as it ended
__global__ void codegen_reader_read(RulesetCoreRead *read)
{
    if (codegen_device_thread() != 0ull)
    {
        return;
    }
    ruleset_core_read(read);
}

// the scratch in one thread (ruleset_core_scratch), since each form's goes on from the forms its lines write
__global__ void codegen_reader_scratch(RulesetCoreScratch *scratch)
{
    if (codegen_device_thread() != 0ull)
    {
        return;
    }
    ruleset_core_scratch(scratch);
}

// device memory as many entries as `sized` holds
template <typename Element> static Element *codegen_reader_take(DeviceArena *memory, const std::vector<Element> &sized)
{
    return codegen_device_take<Element>(memory, sized.size());
}

// `to`, as many entries as it holds, read back from the device's `from`
template <typename Element>
static void codegen_reader_back(DeviceArena *memory, std::vector<Element> *to, const Element *from)
{
    codegen_device_read(memory, to->data(), from, to->size());
}

// `read`'s lists taken on the device, as many entries each as `memory` sized it
static void codegen_reader_memory(DeviceArena *device_arena, const RulesetMemory *memory, RulesetCoreRead *read)
{
    read->letters = codegen_reader_take(device_arena, memory->letters);
    read->pieces = codegen_reader_take(device_arena, memory->pieces);
    read->slots = codegen_reader_take(device_arena, memory->slots);
    read->words = codegen_reader_take(device_arena, memory->words);
    read->banks = codegen_reader_take(device_arena, memory->banks);
    read->fixed = codegen_reader_take(device_arena, memory->fixed);
    read->forms = codegen_reader_take(device_arena, memory->forms);
    read->constructs = codegen_reader_take(device_arena, memory->constructs);
    read->lines = codegen_reader_take(device_arena, memory->lines);
    read->arguments = codegen_reader_take(device_arena, memory->arguments);
    read->bank_given = codegen_reader_take(device_arena, memory->bank_given);
    read->fixed_given = codegen_reader_take(device_arena, memory->fixed_given);
    read->form_given = codegen_reader_take(device_arena, memory->form_given);
    read->building_parameters = codegen_reader_take(device_arena, memory->building_parameters);
}

// what the device's read wrote, read back into `memory`, which `host` points at
static void codegen_reader_read_back(DeviceArena *device_arena, const RulesetCoreRead *ended, RulesetMemory *memory,
                                     RulesetCoreRead *host)
{
    *host = *ended;
    ruleset_memory_size(memory, host);
    codegen_reader_back(device_arena, &memory->letters, ended->letters);
    codegen_reader_back(device_arena, &memory->pieces, ended->pieces);
    codegen_reader_back(device_arena, &memory->slots, ended->slots);
    codegen_reader_back(device_arena, &memory->words, ended->words);
    codegen_reader_back(device_arena, &memory->banks, ended->banks);
    codegen_reader_back(device_arena, &memory->fixed, ended->fixed);
    codegen_reader_back(device_arena, &memory->forms, ended->forms);
    codegen_reader_back(device_arena, &memory->constructs, ended->constructs);
    codegen_reader_back(device_arena, &memory->lines, ended->lines);
    codegen_reader_back(device_arena, &memory->arguments, ended->arguments);
    codegen_reader_back(device_arena, &memory->bank_given, ended->bank_given);
    codegen_reader_back(device_arena, &memory->fixed_given, ended->fixed_given);
    codegen_reader_back(device_arena, &memory->form_given, ended->form_given);
    codegen_reader_back(device_arena, &memory->building_parameters, ended->building_parameters);
}

int ruleset_read_device(Ruleset *rules, const std::string &path, std::string *error)
{
    std::string ruleset_text;
    if (ruleset_file(rules, path, &ruleset_text) == 0)
    {
        return 1;
    }
    RulesetFlat flat;
    ruleset_flat_schema(rules->schema, &flat);
    DeviceArena reader_arena{};
    reader_arena.ok = 1;
    RulesetCoreRead read{};
    read.schema = flat.schema;
    read.schema.letters = codegen_device_copy(&reader_arena, flat.letters.data(), flat.letters.size());
    read.schema.forms = codegen_device_copy(&reader_arena, flat.forms.data(), flat.forms.size());
    read.schema.form_parameters =
        codegen_device_copy(&reader_arena, flat.form_parameters.data(), flat.form_parameters.size());
    read.schema.banks = codegen_device_copy(&reader_arena, flat.banks.data(), flat.banks.size());
    read.schema.fixed = codegen_device_copy(&reader_arena, flat.fixed.data(), flat.fixed.size());
    read.text = codegen_device_copy(&reader_arena, (const unsigned char *)ruleset_text.data(), ruleset_text.size());
    // ruleset_file holds a ruleset below RULESET_FILE_MAX letters
    read.text_length = (unsigned int)ruleset_text.size();
    ruleset_capacities(read.text_length, &read);
    RulesetMemory memory;
    RulesetCoreRead sized = read;
    ruleset_memory_size(&memory, &sized);
    codegen_reader_memory(&reader_arena, &memory, &read);
    RulesetCoreRead *const device_read = codegen_device_copy(&reader_arena, &read, 1ull);
    if (reader_arena.ok != 0)
    {
        codegen_reader_read<<<1u, 1u>>>(device_read);
        codegen_device_launched(&reader_arena);
    }
    RulesetCoreRead ended{};
    codegen_device_read(&reader_arena, &ended, device_read, 1ull);
    RulesetCoreRead host{};
    if (reader_arena.ok != 0)
    {
        codegen_reader_read_back(&reader_arena, &ended, &memory, &host);
    }
    const int ok = reader_arena.ok;
    codegen_device_release(&reader_arena);
    if (ok == 0)
    {
        *error = "the device errored on a call";
        return 0;
    }
    ruleset_keep(&host, ruleset_text, rules);
    return 1;
}

int ruleset_scratch_device(const Ruleset *rules, const unsigned int *banks, std::vector<unsigned int> *scratch,
                           std::string *error)
{
    const unsigned int forms = rules->schema->form_count;
    RulesetFlatConstructs flat;
    ruleset_flat_constructs(rules, &flat);
    DeviceArena scratch_arena{};
    scratch_arena.ok = 1;
    RulesetCoreScratch laid_out{};
    laid_out.constructs = codegen_device_copy(&scratch_arena, flat.constructs.data(), flat.constructs.size());
    laid_out.lines = codegen_device_copy(&scratch_arena, flat.lines.data(), flat.lines.size());
    laid_out.arguments = codegen_device_copy(&scratch_arena, flat.arguments.data(), flat.arguments.size());
    laid_out.form_count = forms;
    laid_out.banks[0] = banks[0];
    laid_out.banks[1] = banks[1];
    laid_out.banks[2] = banks[2];
    scratch->assign((4u * (size_t)forms) + 1u, 0u);
    laid_out.scratch = codegen_reader_take(&scratch_arena, *scratch);
    laid_out.counted = codegen_device_take<unsigned char>(&scratch_arena, (unsigned long long)forms + 1ull);
    laid_out.frames = codegen_device_take<RulesetCoreFrame>(&scratch_arena, (unsigned long long)forms + 1ull);
    laid_out.taken_bank = codegen_reader_take(&scratch_arena, std::vector<unsigned int>(flat.arguments.size()));
    laid_out.taken_number = codegen_reader_take(&scratch_arena, std::vector<unsigned int>(flat.arguments.size()));
    RulesetCoreScratch *const device_scratch = codegen_device_copy(&scratch_arena, &laid_out, 1ull);
    if (scratch_arena.ok != 0)
    {
        codegen_reader_scratch<<<1u, 1u>>>(device_scratch);
        codegen_device_launched(&scratch_arena);
    }
    codegen_reader_back(&scratch_arena, scratch, laid_out.scratch);
    const int ok = scratch_arena.ok;
    codegen_device_release(&scratch_arena);
    scratch->resize(4u * (size_t)forms);
    if (ok == 0)
    {
        *error = "the device errored on a call";
        return 0;
    }
    return 1;
}

#else

int ruleset_read_device(Ruleset *rules, const std::string &path, std::string *error)
{
    (void)rules;
    (void)path;
    *error = "the build has no device";
    return 0;
}

int ruleset_scratch_device(const Ruleset *rules, const unsigned int *banks, std::vector<unsigned int> *scratch,
                           std::string *error)
{
    (void)rules;
    (void)banks;
    scratch->clear();
    *error = "the build has no device";
    return 0;
}

#endif
