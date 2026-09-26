// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef RUN_CFG_H
#define RUN_CFG_H

#include "track.h"

#include <stdio.h>

typedef struct
{
    char *source;
    char *set;
    char *axes;
    char **samples;
    unsigned int count;
    unsigned int first;
    char *species;
    unsigned long long voxel_pm[3];
    unsigned long long membrane_pm;
    char *outputs[7];
    char *view;
    bool floor_entropy;
} RunInputs;

typedef struct
{
    char *bytes;
    size_t length;
    size_t room;
    bool good;
} CfgText;

char *cfg_copy(const char *piece);

bool open_output(TreeRules *rules, RunInputs *inputs, unsigned int output, const char *path);

bool apply_cfg(const char *path, TreeRules *rules, RunInputs *inputs);

bool first_samples(RunInputs *inputs, bool from_source);

bool write_cfg(const TreeRules *rules, const RunInputs *inputs, CfgText *out);

#endif
