// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef CODE_GENERATOR_H
#define CODE_GENERATOR_H

// The register lane, the code generator that names no language: each step unrolled at its widths into
// straight-line text over registers the lane holds itself, every line a form of the language's ruleset. A language of
// this kind is a class that inherits it and names its ruleset's file, the toolchain that builds its text, where its
// header comes from, how many memory writes its text can make in one state, and whether it holds the lane's file and
// signs in the thread block's shared memory (ptx_target.h)

#include "codegen_core.h"
#include "target.h"

#include <map>
#include <string>
#include <vector>

// a budget or a port count that holds anything
#define SCHEDULE_UNBOUNDED 0xFFFFFFFFu

// how a lane is split into states, a clock each: the cost of each form by the name its ruleset gives it, as the
// target's construction set measured it, and the cost of a form it does not name; how much cost a state may chain; and
// how many memory writes a state may make, which the language's own write ports bound as well. The budget and the
// writes are the refinement loop's to choose
struct ScheduleModel
{
    std::map<std::string, unsigned int> cost;
    unsigned int other;
    unsigned int budget;
    unsigned int writes;
};

// a lane as it was split: its states, the most cost one state chains, and the forms that alone cost more than a state
// holds
struct ScheduleReport
{
    unsigned int states;
    unsigned int maximum;
    unsigned int over;
};

// a schedule model as the core splits by it (Schedule): each form's cost by its number, the cost a state may chain, the
// writes the model lets a state make and the language's write ports
struct ScheduleCosts
{
    std::vector<unsigned int> cost;
    unsigned int budget;
    unsigned int writes;
    unsigned int ports;
};

class CodeGenerator : public Target
{
  public:
    std::string program(const EngineRecordLayout *layout, const TargetInfo *target, const std::string &header,
                        unsigned int *places, unsigned int *live) override;

    // the lane split into states by `model`, as program() writes it otherwise; `report` told how it was split
    std::string scheduled(const EngineRecordLayout *layout, const TargetInfo *target, const std::string &header,
                          unsigned int *places, unsigned int *live, const ScheduleModel &model, ScheduleReport *report);

    // the forms program() writes the lane in, as the core decides them (codegen_core.h), in the text's order, the
    // header's place held by an item of the form ASM_PRINTER_ALL_ONES, and the places the lane holds in shared memory;
    // 0 where program() writes nothing for want of a form. The device decides the same (codegen_device.h)
    int decided(const EngineRecordLayout *layout, unsigned int *places, std::vector<MachineInstr> *items);

    // the forms scheduled() writes the lane in, as decided() gives program()'s, and `report` told how it was split
    int decided(const EngineRecordLayout *layout, const ScheduleModel &model, ScheduleReport *report,
                unsigned int *places, std::vector<MachineInstr> *items);

    // `model` as the core splits by it, each form's cost found by the name the ruleset gives it, with the language's
    // write ports, on the host and the device alike
    ScheduleCosts schedule_costs(const ScheduleModel &model) const;

    // the schedule model program() splits the lane by, where the language always splits it into states (a clocked one);
    // NULL where program() writes the lane whole
    virtual const ScheduleModel *program_schedule_model(void) const;

    // 1 where program() splits the lane, `costs` then its model as the core splits by it, for the device to split the
    // same
    int program_schedule_costs(ScheduleCosts *costs) const;

  protected:
    // `shared` is 1 where the language's ruleset lays out the file and its signs in shared memory, a thread's places a
    // word each across the thread block's threads and the signs a byte each after them, as the record machine sizes
    // them: the lane then holds the file's places there and opens by finding its signs
    CodeGenerator(const char *file, const char *toolchain, const char *header, unsigned int write_ports, int shared);

  private:
    int decide(const EngineRecordLayout *layout, const ScheduleModel *model, ScheduleReport *report,
               unsigned int *places, unsigned int *live, std::vector<MachineInstr> *items);

    std::string lane(const EngineRecordLayout *layout, const TargetInfo *target, const std::string &header,
                     unsigned int *places, unsigned int *live, const ScheduleModel *model, ScheduleReport *report);

    unsigned int write_ports;
    int shared;
};

#endif
