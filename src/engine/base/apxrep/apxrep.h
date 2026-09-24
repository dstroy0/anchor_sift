// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef APXREP_H
#define APXREP_H

#include "engine_config.h"

#include <stdio.h>

#ifdef __cplusplus
extern "C" {
#endif

#define APXREP_HEAD_BYTES 16u

#define APXREP_KIND_INPUT "IAPX"
#define APXREP_KIND_CRYSTAL "KCR\0"
#define APXREP_KIND_KEY "IMP\0"
#define APXREP_KIND_OUTPUT "OAPX"
#define APXREP_KIND_BODIES "BAPX"

#define APXREP_VERSION 1u

#define APXREP_INPUT_HEAD_WORDS 12u

int apxrep_head_write(FILE *file, const char *kind);

int apxrep_head_read(FILE *file, const char *kind);

int apxrep_words_write(FILE *file, const unsigned long long *words, size_t count);

int apxrep_words_read(FILE *file, unsigned long long *words, size_t count);

int apxrep_limbs_write(FILE *file, const unsigned int *limbs, size_t count);

int apxrep_limbs_read(FILE *file, unsigned int *limbs, size_t count);

typedef struct
{
    const char *path;
    EngineStream *stream;
    EngineSideSection *section;
    EngineSeal *seal;
    EngineError *error;
} ApxrepInputRequest;

unsigned long long apxrep_input_bytes(const EngineStream *stream, const EngineSideSection *section,
                                      const EngineSeal *seal);

int apxrep_input_write(const ApxrepInputRequest *request);

int apxrep_input_read(const ApxrepInputRequest *request);

int apxrep_input_head(const char *path, EngineStream *stream, EngineSignum *root, EngineError *error);

void apxrep_input_release(EngineStream *stream);

void apxrep_side_release(EngineSideSection *section);

void apxrep_seal_release(EngineSeal *seal);

int apxrep_history_write(const char *path, const EngineHistory *history, EngineError *error);

int apxrep_history_read(const char *path, EngineHistory *history, unsigned int payload, EngineError *error);

void apxrep_history_release(EngineHistory *history);

int apxrep_bodies_write(const char *path, const EngineBodyTable *table, EngineError *error);

int apxrep_bodies_read(const char *path, EngineBodyTable *table, EngineError *error);

void apxrep_bodies_release(EngineBodyTable *table);

#ifdef __cplusplus
}
#endif

#endif
