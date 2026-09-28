// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the target_*.cu pieces share: its includes, types and the functions one piece calls in another
#ifndef TARGET_INTERNAL_H
#define TARGET_INTERNAL_H

#include "ruleset_reader.h"
#include "target.h"

#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>

#include <cstddef>
#include <functional>
#include <initializer_list>
#include <string>
#include <vector>

std::string ruleset_folder(void);

unsigned int ruleset_find(const RulesetName *names, unsigned int count, const std::string &word);

std::string ruleset_entry(Ruleset *rules, const std::string &kind, const std::string &rest);

std::string ruleset_pseudo_line(Ruleset *rules, const std::string &line);

#endif
