// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// run_cfg.h: a cfg read whole, its members found by a dotted path, decimal strings read as exact rationals
#ifndef RUN_CFG_H
#define RUN_CFG_H

#include "sim_rational.h"

#include "cfg_json.h"

#include <string>
#include <vector>

// The text is held whole at its own length and the tokens at one per byte at most; no size is written in. A
// decimal value is a JSON string, "0.0010016", read exactly as a rational; a count is a JSON number.
typedef struct
{
    std::vector<char> text;
    std::vector<CfgJsonToken> tokens;
} RunCfg;

// the cfg at `path` read and parsed: 1, or 0 with the reason written to `line`
int run_cfg_open(const char *path, RunCfg *cfg, ScripturaLine *line);

// the token a dotted path names from the root, "fluid.viscosity": its index, or 0 where a part is missing
unsigned int run_cfg_find(const RunCfg *cfg, const char *path);

// the decimal string at `path` read exactly: 1, or 0 where it is missing or does not read
int run_cfg_rational(const RunCfg *cfg, const char *path, SimRational *value);

// the whole number at `path`: 1, or 0 where it is missing or does not read
int run_cfg_count(const RunCfg *cfg, const char *path, unsigned long long *value);

// the array of decimal strings at `path` read exactly: 1, or 0 where it is missing, empty or an element does not read
int run_cfg_rationals(const RunCfg *cfg, const char *path, std::vector<SimRational> *values);

// the string at `path` as it is written, without escapes read: 1, or 0 where it is missing, empty or not a string
int run_cfg_text(const RunCfg *cfg, const char *path, std::string *value);

// one line naming the members a cfg lacks or could not read
void run_cfg_missing(ScripturaLine *line, const char *members);

// 1 where a value in this module outgrew the build's width
int run_cfg_short(void);

#endif
