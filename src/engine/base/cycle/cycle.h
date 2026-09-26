// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef CYCLE_H
#define CYCLE_H

#include "engine_config.h"

#ifdef __cplusplus
extern "C" {
#endif

#define CYCLE_REFUSED (-1L)

long cycle_key_load(const EngineKeyLayout *layout, CycleKey **key, EngineError *error);

void cycle_key_release(CycleKey *key);

unsigned int cycle_key_scratch_limbs(const CycleKey *key);

typedef struct
{
    const CycleKey *key;
    const Atom *atoms;
    unsigned long long count;
    unsigned int limbs;
    unsigned int *device_out;
    EngineError *error;
} CycleRunRequest;

long cycle_run(const CycleRunRequest *request);

long cycle_record_load(const EngineRecordLayout *layout, CycleRecord **record, EngineError *error);

void cycle_record_release(CycleRecord *record);

unsigned int cycle_record_out_limbs(const CycleRecord *record);

unsigned int cycle_record_members(const CycleRecord *record);

unsigned int cycle_record_in_limbs(const CycleRecord *record, unsigned int member);

// 1 where the loaded program runs as its own compiled kernel, linked against the operator block; 0 where it runs on
// the interpreter (a step the compiler does not hold, NVRTC or nvJitLink not found, or CYCLE_RECORD_INTERPRET=1)
int cycle_record_compiled(const CycleRecord *record);

// the host's copy of the loaded program's block, read back from the device as each launch ends: where it stands,
// sealed whenever no launch holds it. A compiled program runs resident and writes it on the device; a program on the
// interpreter leaves it laid
const EngineProgramBlock *cycle_record_block(const CycleRecord *record);

typedef struct
{
    const CycleRecord *record;
    const unsigned int *device_in[ENGINE_RECORD_MEMBERS_MAX];
    unsigned long long bodies[ENGINE_RECORD_MEMBERS_MAX];
    const unsigned int *device_index;
    unsigned long long count;
    unsigned int *device_out;
    EngineError *error;
} CycleRecordRunRequest;

long cycle_record_run(const CycleRecordRunRequest *request);

typedef struct
{
    const EngineRecordLayout *layout;
    const unsigned int *in[ENGINE_RECORD_MEMBERS_MAX];
    unsigned long long bodies[ENGINE_RECORD_MEMBERS_MAX];
    const unsigned int *index;
    unsigned long long count;
    unsigned int *out;
    EngineError *error;
} CycleRecordHostRequest;

long cycle_record_run_host(const CycleRecordHostRequest *request);

#ifdef __cplusplus
}
#endif

#endif
