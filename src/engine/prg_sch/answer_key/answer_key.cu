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

int hold_answer_key(const AnswerKeyTruth *truth, AnswerKey *key)
{
    memset(key, 0, sizeof(*key));
    const unsigned long long identity_limit = 0x7FFFFFFFFFFFFFFFull;
    int good = (truth->nodes < 0xFFFFFFFFull) && (truth->edges < 0xFFFFFFFFull);
    AnswerKeyNode *const nodes = good ? (AnswerKeyNode *)malloc(((size_t)truth->nodes + 1u) * sizeof(AnswerKeyNode)) : NULL;
    good = good && (nodes != NULL);
    for (unsigned long long node = 0ull; good && (node < truth->nodes); node += 1ull)
    {
        good = (truth->node_identity[node] <= identity_limit);
        nodes[node].identity = (long long)truth->node_identity[node];
        for (unsigned int axis = 0u; good && (axis < 4u); axis += 1u)
        {
            const long long place = truth->node_place[(node * 4ull) + axis];
            good = (place >= 0ll) && (place <= 0x7FFFFFFFll);
            nodes[node].place[axis] = (int)place;
        }
    }
    if (good)
    {
        qsort(nodes, (size_t)truth->nodes, sizeof(AnswerKeyNode), answer_key_order);
    }
    for (unsigned long long node = 1ull; good && (node < truth->nodes); node += 1ull)
    {
        good = (nodes[node - 1ull].identity != nodes[node].identity);
    }
    key->node_count = good ? (unsigned int)truth->nodes : 0u;
    key->edge_count = good ? (unsigned int)truth->edges : 0u;
    key->node_identity = good ? (long long *)malloc(((size_t)key->node_count + 1u) * sizeof(long long)) : NULL;
    key->node_coordinates = good ? (int *)malloc(((size_t)key->node_count + 1u) * 4u * sizeof(int)) : NULL;
    key->edge_ends = good ? (long long *)malloc(((size_t)key->edge_count + 1u) * 2u * sizeof(long long)) : NULL;
    good = good && (key->node_identity != NULL) && (key->node_coordinates != NULL) && (key->edge_ends != NULL);
    for (unsigned int node = 0u; good && (node < key->node_count); node += 1u)
    {
        key->node_identity[node] = nodes[node].identity;
        memcpy(&key->node_coordinates[(size_t)node * 4u], nodes[node].place, sizeof(nodes[node].place));
    }
    for (size_t end = 0u; good && (end < (size_t)key->edge_count * 2u); end += 1u)
    {
        good = (truth->edge_ends[end] <= identity_limit);
        key->edge_ends[end] = (long long)truth->edge_ends[end];
    }
    free(nodes);
    if (good == 0)
    {
        release_answer_key(key);
    }
    return good;
}

void release_answer_key(AnswerKey *key)
{
    free(key->node_identity);
    free(key->node_coordinates);
    free(key->edge_ends);
    memset(key, 0, sizeof(*key));
}
