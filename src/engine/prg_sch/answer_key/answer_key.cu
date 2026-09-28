// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "answer_key.h"

#include "track.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct
{
    long long identity;
    int place[4];
} AnswerKeyNode;

long node_slot_of(const AnswerKey *key, long long identity)
{
    unsigned int low = 0u;
    unsigned int high = key->node_count;
    while (low < high)
    {
        const unsigned int middle = low + (high - low) / 2u;
        if (key->node_identity[middle] < identity)
        {
            low = middle + 1u;
        }
        else
        {
            high = middle;
        }
    }
    return ((low < key->node_count) && (key->node_identity[low] == identity)) ? (long)low : -1L;
}

static int answer_key_order(const void *left, const void *right)
{
    const long long one = ((const AnswerKeyNode *)left)->identity;
    const long long other = ((const AnswerKeyNode *)right)->identity;
    return (one > other) - (one < other);
}

int answer_key_build(const AnswerKeyTruth *truth, AnswerKey *key)
{
    memset(key, 0, sizeof(*key));
    const unsigned long long identity_limit = 0x7FFFFFFFFFFFFFFFull;
    int ok = (truth->nodes < 0xFFFFFFFFull) && (truth->edges < 0xFFFFFFFFull);
    AnswerKeyNode *const nodes =
        ok ? (AnswerKeyNode *)malloc(((size_t)truth->nodes + 1u) * sizeof(AnswerKeyNode)) : NULL;
    ok = ok && (nodes != NULL);
    for (unsigned long long node = 0ull; ok && (node < truth->nodes); node += 1ull)
    {
        ok = (truth->node_identity[node] <= identity_limit);
        nodes[node].identity = (long long)truth->node_identity[node];
        for (unsigned int axis = 0u; ok && (axis < 4u); axis += 1u)
        {
            const long long place = truth->node_place[(node * 4ull) + axis];
            ok = (place >= 0ll) && (place <= 0x7FFFFFFFll);
            nodes[node].place[axis] = (int)place;
        }
    }
    if (ok)
    {
        qsort(nodes, (size_t)truth->nodes, sizeof(AnswerKeyNode), answer_key_order);
    }
    for (unsigned long long node = 1ull; ok && (node < truth->nodes); node += 1ull)
    {
        ok = (nodes[node - 1ull].identity != nodes[node].identity);
    }
    key->node_count = ok ? (unsigned int)truth->nodes : 0u;
    key->edge_count = ok ? (unsigned int)truth->edges : 0u;
    key->node_identity = ok ? (long long *)malloc(((size_t)key->node_count + 1u) * sizeof(long long)) : NULL;
    key->node_coordinates = ok ? (int *)malloc(((size_t)key->node_count + 1u) * 4u * sizeof(int)) : NULL;
    key->edge_ends = ok ? (long long *)malloc(((size_t)key->edge_count + 1u) * 2u * sizeof(long long)) : NULL;
    ok = ok && (key->node_identity != NULL) && (key->node_coordinates != NULL) && (key->edge_ends != NULL);
    for (unsigned int node = 0u; ok && (node < key->node_count); node += 1u)
    {
        key->node_identity[node] = nodes[node].identity;
        memcpy(&key->node_coordinates[(size_t)node * 4u], nodes[node].place, sizeof(nodes[node].place));
    }
    for (size_t end = 0u; ok && (end < (size_t)key->edge_count * 2u); end += 1u)
    {
        ok = (truth->edge_ends[end] <= identity_limit);
        key->edge_ends[end] = (long long)truth->edge_ends[end];
    }
    free(nodes);
    if (ok == 0)
    {
        release_answer_key(key);
    }
    return ok;
}

void release_answer_key(AnswerKey *key)
{
    free(key->node_identity);
    free(key->node_coordinates);
    free(key->edge_ends);
    memset(key, 0, sizeof(*key));
}
