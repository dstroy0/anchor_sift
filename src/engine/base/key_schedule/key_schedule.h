// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef KEY_SCHEDULE_H
#define KEY_SCHEDULE_H

#include "engine_config.h"

#ifdef __cplusplus
extern "C" {
#endif

#define KEY_SCHEDULE_REFUSED (-1L)

long key_schedule_lay(const EngineKey *key, EngineKeyLayout *layout, EngineError *error);

void key_schedule_release(EngineKeyLayout *layout);

typedef struct
{
    const EngineRecordKey *key;
    const unsigned int *field_offset;
    unsigned int fields;
    const unsigned int *in_limbs;
    // When set, a register is freed once no later step reads it; a long chain runs within the
    // file's ENGINE_RECORD_LIMBS_MOST limbs. When clear, every step keeps its own register for the
    // whole run, the layout the proven programs were measured against.
    int reuse;
    EngineRecordLayout *layout;
    EngineError *error;
} KeyScheduleRecordRequest;

long key_schedule_record_lay(const KeyScheduleRecordRequest *request);

void key_schedule_record_release(EngineRecordLayout *layout);

#ifdef __cplusplus
}
#endif

#endif
