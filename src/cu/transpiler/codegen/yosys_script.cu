// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "yosys_script.h"

#include "ruleset_reader.h"

// the script's forms, by their places in the schema
enum YosysForm
{
    YOSYS_READ_SOURCE = 0,
    YOSYS_COARSE = 1,
    YOSYS_MEMORIES = 2,
    YOSYS_FINE = 3,
    YOSYS_MEASURE = 4,
    YOSYS_FORM_COUNT = 5
};

static const RulesetName s_yosys_forms[YOSYS_FORM_COUNT] = {
    {"read_source", 1u}, {"coarse", 1u}, {"memories", 1u}, {"fine", 0u}, {"measure", 0u}};

// the script's forms and no bank or fixed register, read from yosys.krs, which Yosys reads and whose opening line is
// the ruleset's own read_source
static const RulesetSchema s_yosys_schema = {
    "yosys.krs", "yosys", "read_source", s_yosys_forms, YOSYS_FORM_COUNT, NULL, 0u, NULL, 0u};

YosysScript::YosysScript(void) : Target(&s_yosys_schema)
{
}

std::string YosysScript::program(const EngineRecordLayout *layout, const TargetInfo *target, const std::string &header,
                                 unsigned int *places, unsigned int *live)
{
    (void)layout;
    (void)target;
    (void)header;
    *places = 0u;
    *live = 0u;
    return std::string();
}

std::string YosysScript::synthesis(const std::string &source, const std::string &top, const std::string &memories)
{
    const Ruleset *const rules = ruleset(1);
    if (rules == NULL)
    {
        return std::string();
    }
    std::string text;
    int broken = 0;
    ruleset_write(rules, text, YOSYS_READ_SOURCE, {source}, &broken);
    ruleset_write(rules, text, YOSYS_COARSE, {top}, &broken);
    if (!memories.empty())
    {
        ruleset_write(rules, text, YOSYS_MEMORIES, {memories}, &broken);
    }
    ruleset_write(rules, text, YOSYS_FINE, {}, &broken);
    ruleset_write(rules, text, YOSYS_MEASURE, {}, &broken);
    return (broken == 0) ? text : std::string();
}

YosysScript &yosys_script(void)
{
    static YosysScript script;
    return script;
}
