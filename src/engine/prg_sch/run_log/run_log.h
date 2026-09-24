// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef RUN_LOG_H
#define RUN_LOG_H

#include "track.h"

#include <stdio.h>

extern const char *g_log_path;

extern char g_rules_line[256];

void rules_line(const TreeRules *rules, char *line, size_t room);

FILE *log_open(void);

void log_when(char *when, size_t room);

const char *log_rules(void);

#endif
