// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef SCRIPTURA_ARM_H
#define SCRIPTURA_ARM_H

#include "scriptura.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct
{
    const char *name;
    unsigned long long width;
    unsigned long long (*length)(const char *text, unsigned long long room);
    unsigned long long (*find)(const void *from, unsigned char value, unsigned long long bytes);
    void (*copy)(void *to, const void *from, unsigned long long bytes);
    void (*move_up)(void *to, const void *from, unsigned long long bytes);
    int (*compare)(const void *one, const void *other, unsigned long long bytes);
    void (*fill)(void *to, unsigned char value, unsigned long long bytes);
} ScripturaArm;

unsigned long long scriptura_portable_length(const char *text, unsigned long long room);

unsigned long long scriptura_portable_find(const void *from, unsigned char value, unsigned long long bytes);

void scriptura_portable_copy(void *to, const void *from, unsigned long long bytes);

void scriptura_portable_move_up(void *to, const void *from, unsigned long long bytes);

int scriptura_portable_compare(const void *one, const void *other, unsigned long long bytes);

void scriptura_portable_fill(void *to, unsigned char value, unsigned long long bytes);

const ScripturaArm *scriptura_portable_arm(void);

const ScripturaArm *scriptura_avx2_arm(void);

const ScripturaArm *scriptura_avx512_arm(void);

const ScripturaArm *scriptura_neon_arm(void);

const ScripturaArm *scriptura_sve_arm(void);

#ifdef __cplusplus
}
#endif

#endif
