/* cell_tracking - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file heaviest_matching.c
 * @brief heaviest_matching.h in portable C11: successive shortest paths, integer costs, per component.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-16
 *
 * @warning Path costs are held in signed 64 bits. A component's potentials are bounded by its pair
 *          count times the largest count, so a component of more than 2^31 pairs each sharing near
 *          2^32 voxels could overflow. A 4,194,304 voxel frame cannot produce one.
 */

#include "heaviest_matching.h"

#include <stdlib.h>
#include <string.h>

_Static_assert(sizeof(long long) == 8u, "heaviest_matching: long long must be 64 bits, a path cost");

/** @brief A distance no path reaches. */
#define MATCHING_UNREACHED 0x7FFFFFFFFFFFFFFFll

/** @brief One component's flow graph, in compressed adjacency form. */
typedef struct
{
    int *head;
    int *next;
    int *target;
    int *capacity;
    long long *cost;
    int edges;
} MatchingGraph;

/** @brief A binary heap of (distance, node), smallest distance first, lower node on ties. */
typedef struct
{
    long long *distance;
    int *node;
    int size;
} MatchingHeap;

/**
 * @brief Whether heap slot `left` should sit above slot `right`.
 *
 * @param[in] heap  The heap [BORROWS].
 * @param[in] left  One slot.
 * @param[in] right The other.
 * @return          1 where left comes first.
 */
static int matching_heap_before(const MatchingHeap *heap, int left, int right)
{
    if (heap->distance[left] != heap->distance[right])
    {
        return (heap->distance[left] < heap->distance[right]) ? 1 : 0;
    }
    return (heap->node[left] < heap->node[right]) ? 1 : 0;
}

/**
 * @brief Swaps two heap slots.
 *
 * @param[in,out] heap  The heap [BORROWS].
 * @param[in]     left  One slot.
 * @param[in]     right The other.
 */
static void matching_heap_swap(MatchingHeap *heap, int left, int right)
{
    const long long distance = heap->distance[left];
    const int node = heap->node[left];
    heap->distance[left] = heap->distance[right];
    heap->node[left] = heap->node[right];
    heap->distance[right] = distance;
    heap->node[right] = node;
}

/**
 * @brief Pushes an entry.
 *
 * @param[in,out] heap     The heap, with room for the entry [BORROWS].
 * @param[in]     distance Its distance.
 * @param[in]     node     Its node.
 */
static void matching_heap_push(MatchingHeap *heap, long long distance, int node)
{
    int slot = heap->size;
    heap->distance[slot] = distance;
    heap->node[slot] = node;
    heap->size += 1;
    while (slot > 0)
    {
        const int parent = (slot - 1) / 2;
        if (matching_heap_before(heap, slot, parent) == 0)
        {
            break;
        }
        matching_heap_swap(heap, slot, parent);
        slot = parent;
    }
}

/**
 * @brief Pops the first entry into `distance` and `node`.
 *
 * @param[in,out] heap     A non-empty heap [BORROWS].
 * @param[out]    distance Its distance [BORROWS].
 * @param[out]    node     Its node [BORROWS].
 */
static void matching_heap_pop(MatchingHeap *heap, long long *distance, int *node)
{
    *distance = heap->distance[0];
    *node = heap->node[0];
    heap->size -= 1;
    heap->distance[0] = heap->distance[heap->size];
    heap->node[0] = heap->node[heap->size];
    int slot = 0;
    for (;;)
    {
        const int left = (2 * slot) + 1;
        const int right = left + 1;
        int first = slot;
        if ((left < heap->size) && (matching_heap_before(heap, left, first) != 0))
        {
            first = left;
        }
        if ((right < heap->size) && (matching_heap_before(heap, right, first) != 0))
        {
            first = right;
        }
        if (first == slot)
        {
            break;
        }
        matching_heap_swap(heap, slot, first);
        slot = first;
    }
}

/**
 * @brief Adds an edge and its residual twin, which sits at the next index.
 *
 * @param[in,out] graph  The graph, with room for two more edges [BORROWS].
 * @param[in]     from   Tail node.
 * @param[in]     to     Head node.
 * @param[in]     weight Cost of the forward edge.
 */
static void matching_edge(MatchingGraph *graph, int from, int to, long long weight)
{
    const int forward = graph->edges;
    graph->target[forward] = to;
    graph->capacity[forward] = 1;
    graph->cost[forward] = weight;
    graph->next[forward] = graph->head[from];
    graph->head[from] = forward;
    graph->target[forward + 1] = from;
    graph->capacity[forward + 1] = 0;
    graph->cost[forward + 1] = -weight;
    graph->next[forward + 1] = graph->head[to];
    graph->head[to] = forward + 1;
    graph->edges += 2;
}

/**
 * @brief Finds the root of a union-find element, halving the path as it goes.
 *
 * @param[in,out] parent The forest [BORROWS].
 * @param[in]     item   The element.
 * @return               Its root.
 */
static unsigned int matching_root(unsigned int *parent, unsigned int item)
{
    while (parent[item] != item)
    {
        parent[item] = parent[parent[item]];
        item = parent[item];
    }
    return item;
}

/**
 * @brief Solves one component and marks its chosen pairs.
 *
 * @param[in]  args        The request [BORROWS].
 * @param[in]  members     Indices of this component's pairs, ascending [BORROWS].
 * @param[in]  member_count How many.
 * @param[in]  local       Scratch mapping objects to local nodes, all -1 on entry and on return [BORROWS].
 * @param[out] chosen      Staged choices [BORROWS].
 * @return                 Pairs chosen, or -1 where memory ran out.
 */
static long matching_component(const HeaviestMatchingRequest *args, const unsigned int *members,
                               unsigned int member_count, int *local, unsigned char *chosen)
{
    // Local node numbers: source 0, then every before, then every after, then the sink.
    int befores = 0;
    int afters = 0;
    for (unsigned int member = 0u; member < member_count; member += 1u)
    {
        const unsigned int pair = members[member];
        if (local[args->before[pair]] < 0)
        {
            befores += 1;
            local[args->before[pair]] = befores;
        }
    }
    for (unsigned int member = 0u; member < member_count; member += 1u)
    {
        const unsigned int pair = members[member];
        const unsigned int slot = args->before_count + args->after[pair];
        if (local[slot] < 0)
        {
            afters += 1;
            local[slot] = befores + afters;
        }
    }
    const int nodes = befores + afters + 2;
    const int sink = nodes - 1;
    // Narrowing is safe: the member count is at most the pair count, itself an unsigned int, and a
    // component this size would have exhausted memory long before the edge count neared INT_MAX.
    const int edge_room = 2 * (befores + afters + (int)member_count);

    MatchingGraph graph;
    graph.head = (int *)malloc((size_t)nodes * sizeof(int));
    graph.next = (int *)malloc((size_t)edge_room * sizeof(int));
    graph.target = (int *)malloc((size_t)edge_room * sizeof(int));
    graph.capacity = (int *)malloc((size_t)edge_room * sizeof(int));
    graph.cost = (long long *)malloc((size_t)edge_room * sizeof(long long));
    graph.edges = 0;
    long long *const potential = (long long *)malloc((size_t)nodes * sizeof(long long));
    long long *const distance = (long long *)malloc((size_t)nodes * sizeof(long long));
    int *const arrived = (int *)malloc((size_t)nodes * sizeof(int));
    unsigned char *const settled = (unsigned char *)malloc((size_t)nodes);
    MatchingHeap heap;
    heap.distance = (long long *)malloc(((size_t)edge_room + 1u) * sizeof(long long));
    heap.node = (int *)malloc(((size_t)edge_room + 1u) * sizeof(int));
    heap.size = 0;

    long answer = -1;
    if ((graph.head != NULL) && (graph.next != NULL) && (graph.target != NULL) && (graph.capacity != NULL)
     && (graph.cost != NULL) && (potential != NULL) && (distance != NULL) && (arrived != NULL)
     && (settled != NULL) && (heap.distance != NULL) && (heap.node != NULL))
    {
        for (int node = 0; node < nodes; node += 1)
        {
            graph.head[node] = -1;
            potential[node] = 0ll;
        }
        for (int before = 1; before <= befores; before += 1)
        {
            matching_edge(&graph, 0, before, 0ll);
        }
        for (unsigned int member = 0u; member < member_count; member += 1u)
        {
            const unsigned int pair = members[member];
            const int from = local[args->before[pair]];
            const int to = local[args->before_count + args->after[pair]];
            // Widening a count to long long is exact; negated, it is the cost of carrying that overlap.
            const long long weight = -(long long)args->counts[pair];
            matching_edge(&graph, from, to, weight);
            if (weight < potential[to])
            {
                potential[to] = weight;
            }
        }
        for (int after = befores + 1; after < sink; after += 1)
        {
            matching_edge(&graph, after, sink, 0ll);
            if (potential[after] < potential[sink])
            {
                potential[sink] = potential[after];
            }
        }

        answer = 0;
        for (;;)
        {
            for (int node = 0; node < nodes; node += 1)
            {
                distance[node] = MATCHING_UNREACHED;
                arrived[node] = -1;
                settled[node] = 0u;
            }
            distance[0] = 0ll;
            heap.size = 0;
            matching_heap_push(&heap, 0ll, 0);
            while (heap.size > 0)
            {
                long long reached = 0ll;
                int node = 0;
                matching_heap_pop(&heap, &reached, &node);
                if (settled[node] != 0u)
                {
                    continue;
                }
                settled[node] = 1u;
                for (int edge = graph.head[node]; edge >= 0; edge = graph.next[edge])
                {
                    if (graph.capacity[edge] <= 0)
                    {
                        continue;
                    }
                    const int next = graph.target[edge];
                    const long long candidate = reached + graph.cost[edge] + potential[node] - potential[next];
                    if (candidate < distance[next])
                    {
                        distance[next] = candidate;
                        arrived[next] = edge;
                        matching_heap_push(&heap, candidate, next);
                    }
                }
            }
            if (distance[sink] == MATCHING_UNREACHED)
            {
                break;
            }
            const long long true_cost = distance[sink] - potential[0] + potential[sink];
            if (true_cost >= 0ll)
            {
                break;
            }
            const long long cap = distance[sink];
            for (int node = 0; node < nodes; node += 1)
            {
                potential[node] += (distance[node] < cap) ? distance[node] : cap;
            }
            for (int node = sink; node != 0; node = graph.target[arrived[node] ^ 1])
            {
                graph.capacity[arrived[node]] -= 1;
                graph.capacity[arrived[node] ^ 1] += 1;
            }
            answer += 1;
        }

        // Pair edges follow the source edges, one forward edge per member in member order.
        for (unsigned int member = 0u; member < member_count; member += 1u)
        {
            // Narrowing is safe: the edge index stays below edge_room, an int.
            const int forward = (2 * befores) + (2 * (int)member);
            chosen[members[member]] = (graph.capacity[forward] == 0) ? 1u : 0u;
        }
    }

    for (unsigned int member = 0u; member < member_count; member += 1u)
    {
        const unsigned int pair = members[member];
        local[args->before[pair]] = -1;
        local[args->before_count + args->after[pair]] = -1;
    }
    free(graph.head);
    free(graph.next);
    free(graph.target);
    free(graph.capacity);
    free(graph.cost);
    free(potential);
    free(distance);
    free(arrived);
    free(settled);
    free(heap.distance);
    free(heap.node);
    return answer;
}

long heaviest_matching_run(const HeaviestMatchingRequest *args)
{
    if ((args == NULL) || ((args->pairs != 0u) && ((args->before == NULL) || (args->after == NULL)
                                                   || (args->counts == NULL) || (args->chosen == NULL)))
     || (args->before_count > 0x3FFFFFFFu) || (args->after_count > 0x3FFFFFFFu) || (args->pairs > 0x3FFFFFFFu))
    {
        return HEAVIEST_MATCHING_REFUSED;
    }
    for (unsigned int pair = 0u; pair < args->pairs; pair += 1u)
    {
        if ((args->before[pair] >= args->before_count) || (args->after[pair] >= args->after_count)
         || (args->counts[pair] == 0u))
        {
            return HEAVIEST_MATCHING_REFUSED;
        }
    }
    // Widening to size_t is exact; both counts were just bounded below 2^30.
    const size_t objects = (size_t)args->before_count + (size_t)args->after_count;
    unsigned int *const parent = (unsigned int *)malloc((objects + 1u) * sizeof(unsigned int));
    unsigned int *const component_of = (unsigned int *)malloc(((size_t)args->pairs + 1u) * sizeof(unsigned int));
    unsigned int *const starts = (unsigned int *)calloc(objects + 2u, sizeof(unsigned int));
    unsigned int *const members = (unsigned int *)malloc(((size_t)args->pairs + 1u) * sizeof(unsigned int));
    int *const local = (int *)malloc((objects + 1u) * sizeof(int));
    unsigned char *const staged = (unsigned char *)calloc((size_t)args->pairs + 1u, 1u);
    long answer = HEAVIEST_MATCHING_REFUSED;
    if ((parent != NULL) && (component_of != NULL) && (starts != NULL) && (members != NULL) && (local != NULL)
     && (staged != NULL))
    {
        for (size_t object = 0u; object < objects; object += 1u)
        {
            // Narrowing is safe: objects is below 2^31.
            parent[object] = (unsigned int)object;
            local[object] = -1;
        }
        for (unsigned int pair = 0u; pair < args->pairs; pair += 1u)
        {
            const unsigned int left = matching_root(parent, args->before[pair]);
            const unsigned int right = matching_root(parent, args->before_count + args->after[pair]);
            if (left != right)
            {
                parent[right] = left;
            }
        }
        // Pairs grouped by component root with a counting sort, keeping pair order inside each group.
        for (unsigned int pair = 0u; pair < args->pairs; pair += 1u)
        {
            component_of[pair] = matching_root(parent, args->before[pair]);
            starts[component_of[pair] + 1u] += 1u;
        }
        for (size_t object = 0u; object < objects; object += 1u)
        {
            starts[object + 1u] += starts[object];
        }
        unsigned int *const filled = (unsigned int *)malloc((objects + 1u) * sizeof(unsigned int));
        if (filled != NULL)
        {
            memcpy(filled, starts, (objects + 1u) * sizeof(unsigned int));
            for (unsigned int pair = 0u; pair < args->pairs; pair += 1u)
            {
                members[filled[component_of[pair]]] = pair;
                filled[component_of[pair]] += 1u;
            }
            free(filled);
            answer = 0;
            for (size_t object = 0u; (object < objects) && (answer >= 0); object += 1u)
            {
                const unsigned int count = starts[object + 1u] - starts[object];
                if (count == 0u)
                {
                    continue;
                }
                const long chosen = matching_component(args, &members[starts[object]], count, local, staged);
                answer = (chosen < 0) ? HEAVIEST_MATCHING_REFUSED : (answer + chosen);
            }
            if (answer >= 0)
            {
                memcpy(args->chosen, staged, (size_t)args->pairs);
            }
        }
    }
    free(parent);
    free(component_of);
    free(starts);
    free(members);
    free(local);
    free(staged);
    return answer;
}
