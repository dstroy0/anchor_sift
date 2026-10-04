// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// report.h: exact values written as d.ddd... e n, their first digit and `places` more, truncated, every step exact
#ifndef REPORT_H
#define REPORT_H

#include "sim_rational.h"

void report_value(ScripturaLine *line, SimRational value, unsigned int places);

// "  name = value unit"
void report_line(ScripturaLine *line, const char *name, SimRational value, const char *unit, unsigned int places);

// "  name between low and high unit"
void report_interval(ScripturaLine *line, const char *name, SimRational low, SimRational high, const char *unit,
                     unsigned int places);

// 1 where a value in this module outgrew the build's width
int report_short(void);

#endif
