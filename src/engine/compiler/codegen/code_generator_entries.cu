// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// code_generator_entries.cu: the code generator's entry points, each a call of decide() or lane() with the program's
// schedule model or a given one
#include "code_generator.h"

#include <string>
#include <vector>

std::string CodeGenerator::program(const EngineRecordLayout *layout, const TargetInfo *target,
                                   const std::string &header, unsigned int *places, unsigned int *live)
{
    ScheduleReport report{};
    return lane(layout, target, header, places, live, program_schedule_model(), &report);
}

const ScheduleModel *CodeGenerator::program_schedule_model(void) const
{
    return NULL;
}

unsigned int CodeGenerator::register_file_holds(void) const
{
    return 0u;
}

int CodeGenerator::program_schedule_costs(ScheduleCosts *costs) const
{
    const ScheduleModel *const model = program_schedule_model();
    if (model == NULL)
    {
        return 0;
    }
    *costs = schedule_costs(*model);
    return 1;
}

std::string CodeGenerator::scheduled(const EngineRecordLayout *layout, const TargetInfo *target,
                                     const std::string &header, unsigned int *places, unsigned int *live,
                                     const ScheduleModel &model, ScheduleReport *report)
{
    return lane(layout, target, header, places, live, &model, report);
}

int CodeGenerator::decided(const EngineRecordLayout *layout, unsigned int *places, std::vector<MachineInstr> *items)
{
    unsigned int live = 0u;
    ScheduleReport report{};
    return decide(layout, program_schedule_model(), &report, places, &live, items);
}

int CodeGenerator::decided(const EngineRecordLayout *layout, const ScheduleModel &model, ScheduleReport *report,
                           unsigned int *places, std::vector<MachineInstr> *items)
{
    unsigned int live = 0u;
    return decide(layout, &model, report, places, &live, items);
}
