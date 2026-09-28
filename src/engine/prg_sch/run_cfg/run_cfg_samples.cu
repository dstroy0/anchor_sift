// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// run_cfg_samples.cu: the run's samples, the first of the source's or the set's
#include "run_cfg.h"

#include "engine.h"

#include <stdlib.h>

bool first_samples(RunInputs *inputs, bool from_source)
{
    const char *const directory = from_source ? inputs->source : inputs->set;
    char **names = NULL;
    const size_t count = (directory != NULL) ? (size_t)(from_source ? engine_source_samples(directory, &names)
                                                                    : engine_set_samples(directory, &names))
                                             : 0u;
    const size_t kept = (count < inputs->first) ? count : inputs->first;
    for (size_t slot = kept; slot < count; slot += 1u)
    {
        free(names[slot]);
    }
    for (unsigned int slot = 0u; slot < inputs->count; slot += 1u)
    {
        free(inputs->samples[slot]);
    }
    free(inputs->samples);
    inputs->samples = names;
    inputs->count = (unsigned int)kept;
    return kept != 0u;
}
