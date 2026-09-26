// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef ANSWER_KEY_H
#define ANSWER_KEY_H

#include "track.h"

typedef struct
{
    unsigned long long nodes;
    unsigned long long edges;
    const unsigned long long *node_identity;
    const long long *node_place;
    const unsigned long long *edge_ends;
} AnswerKeyTruth;

long node_slot_of(const AnswerKey *key, long long identity);

int hold_answer_key(const AnswerKeyTruth *truth, AnswerKey *key);

void release_answer_key(AnswerKey *key);

#endif
