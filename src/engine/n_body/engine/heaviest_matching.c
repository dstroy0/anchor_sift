/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file heaviest_matching.c
 * @brief Heaviest bipartite matching as a minimum cost flow, one connected component at a time.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-18
 *
 * @note Each component becomes a flow network: a source joined to every before object, a pair
 *       edge from its before object to its after object costing minus its count, and every after
 *       object joined to a sink, every edge carrying one unit. Sending flow along the cheapest path
 *       while that path costs less than zero keeps adding the pair that raises the matched weight
 *       most, and stops at the heaviest matching.
 * @note The cheapest path is found by Dijkstra over reduced costs, cost plus the potential of the
 *       edge's tail minus that of its head, which stay non-negative when the potentials are kept up
 *       to date. Every cost, potential and distance is a 64 bit integer.
 */

#include "heaviest_matching.h"

#include <stdlib.h>
#include <string.h>

_Static_assert(sizeof(long long) == 8u, "heaviest_matching: long long must be 64 bits, a path cost");

/** @brief A distance no path reaches, above any sum of counts the limits in the entry allow. */
#define MATCHING_UNREACHED 0x7FFFFFFFFFFFFFFFll

/**
 * @brief A flow network as adjacency lists of paired edges.
 *
 * @note Edge e and edge e ^ 1 are a forward edge and its reverse. Pushing a unit along one takes a
 *       unit of capacity from it and gives one to the other.
 */
typedef struct
{
    int *head;         /**< First edge leaving each node, or -1 [BORROWS]. */
    int *next;         /**< Next edge leaving the same node, or -1 [BORROWS]. */
    int *target;       /**< Node each edge enters [BORROWS]. */
    int *capacity;     /**< Units each edge can still carry [BORROWS]. */
    long long *cost;   /**< Cost of one unit along each edge [BORROWS]. */
    int edges;         /**< Edges added so far, forward and reverse both counted. */
} MatchingGraph;

/** @brief A binary min-heap of (distance, node) entries for Dijkstra. */
typedef struct
{
    long long *distance; /**< Distance of each entry [BORROWS]. */
    int *node;           /**< Node of each entry [BORROWS]. */
    int size;            /**< Entries held. */
} MatchingHeap;

/**
 * @brief Whether one heap entry orders before another.
 *
 * @param[in] heap  The heap [BORROWS].
 * @param[in] left  One entry.
 * @param[in] right The other entry.
 * @return          1 where `left` has the smaller distance, or the same distance and the smaller
 *                  node, 0 otherwise.
 * @note The node index breaks ties. Two nodes at one distance are settled in index order on every
 *       run, and the matching chosen does not depend on the order entries arrived in.
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
 * @brief Exchanges two heap entries.
 *
 * @param[in,out] heap  The heap [BORROWS].
 * @param[in]     left  One entry.
 * @param[in]     right The other entry.
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
 * @brief Adds an entry and sifts it up to its place.
 *
 * @param[in,out] heap     The heap [BORROWS].
 * @param[in]     distance The entry's distance.
 * @param[in]     node     The entry's node.
 * @note The caller sizes the heap for one entry per edge plus the start, the most a Dijkstra pass
 *       can push, and nothing here checks it.
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
 * @brief Removes the least entry and restores the heap.
 *
 * @param[in,out] heap     The heap, holding at least one entry [BORROWS].
 * @param[out]    distance The removed entry's distance [BORROWS].
 * @param[out]    node     The removed entry's node [BORROWS].
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
 * @brief Adds a unit capacity edge and its zero capacity reverse.
 *
 * @param[in,out] graph  The network [BORROWS].
 * @param[in]     from   Node the edge leaves.
 * @param[in]     to     Node the edge enters.
 * @param[in]     weight Cost of the unit. The reverse costs its negation.
 * @note The forward edge takes the next even index and its reverse the odd index after it.
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
 * @brief Finds the root of an object's set, halving the path as it walks.
 *
 * @param[in,out] parent Each object's parent in the union-find forest [BORROWS].
 * @param[in]     item   The object.
 * @return               The root of the set holding `item`.
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
 * @brief Matches one connected component and marks the pairs it keeps.
 *
 * @param[in]     args         The whole request, read for its pairs [BORROWS].
 * @param[in]     members      The pair indices in this component [BORROWS].
 * @param[in]     member_count How many pairs.
 * @param[in,out] local        Scratch mapping each object to its node here, -1 outside; left all
 *                             -1 again on return [BORROWS].
 * @param[out]    chosen       One byte per pair of the whole request, written for this
 *                             component's pairs [BORROWS].
 * @return                     Pairs kept in this component, or -1 where an allocation failed.
 * @note Node 0 is the source, nodes 1 onward the before objects, then the after objects, and the
 *       last node the sink.
 */
static long matching_component(const HeaviestMatchingRequest *args, const unsigned int *members,
                               unsigned int member_count, int *local, unsigned char *chosen)
{

    // Number the component's before objects from 1, then its after objects after them. local holds
    // before objects at their own index and after objects past before_count, so one scratch array
    // serves both sides.
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

    // Two edges, forward and reverse, for each source edge, sink edge and pair edge.
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
        // The starting potentials are the shortest distances from the source in the network with
        // no flow: 0 at every before object, the cheapest incoming pair at every after object, and
        // the cheapest of those at the sink. Every reduced cost then starts at zero or above, which
        // is what lets the first Dijkstra pass run over negative pair costs.
        for (unsigned int member = 0u; member < member_count; member += 1u)
        {
            const unsigned int pair = members[member];
            const int from = local[args->before[pair]];
            const int to = local[args->before_count + args->after[pair]];

            // A heavier pair is a cheaper edge, so the cheapest path adds the most weight.
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
                // A node can be pushed more than once. Only its first pop is its shortest distance.
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
            // The reduced distance back in real cost. A path costing zero or more would add no
            // weight, and the matching is the heaviest there is.
            const long long true_cost = distance[sink] - potential[0] + potential[sink];
            if (true_cost >= 0ll)
            {
                break;
            }
            // Raise every potential by its distance, capped at the sink's. A node the pass never
            // reached keeps the cap, not MATCHING_UNREACHED, and its potential stays finite.
            const long long cap = distance[sink];
            for (int node = 0; node < nodes; node += 1)
            {
                potential[node] += (distance[node] < cap) ? distance[node] : cap;
            }
            // Push one unit back along the path, from the sink to the source through each node's
            // arriving edge. The reverse of an edge leaves the node the edge entered.
            for (int node = sink; node != 0; node = graph.target[arrived[node] ^ 1])
            {
                graph.capacity[arrived[node]] -= 1;
                graph.capacity[arrived[node] ^ 1] += 1;
            }
            answer += 1;
        }

        for (unsigned int member = 0u; member < member_count; member += 1u)
        {

            // The source edges took the first 2 * befores indices, and the pair edges followed in
            // member order, two each. A pair edge left with no capacity carried its unit.
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

    const size_t objects = (size_t)args->before_count + (size_t)args->after_count;
    unsigned int *const parent = (unsigned int *)malloc((objects + 1u) * sizeof(unsigned int));
    unsigned int *const component_of = (unsigned int *)malloc(((size_t)args->pairs + 1u) * sizeof(unsigned int));
    unsigned int *const starts = (unsigned int *)calloc(objects + 2u, sizeof(unsigned int));
    unsigned int *const members = (unsigned int *)malloc(((size_t)args->pairs + 1u) * sizeof(unsigned int));
    int *const local = (int *)malloc((objects + 1u) * sizeof(int));
    // The choice is built here and copied out whole, so a refusal part way leaves `chosen` as it was.
    unsigned char *const staged = (unsigned char *)calloc((size_t)args->pairs + 1u, 1u);
    long answer = HEAVIEST_MATCHING_REFUSED;
    if ((parent != NULL) && (component_of != NULL) && (starts != NULL) && (members != NULL) && (local != NULL)
     && (staged != NULL))
    {
        for (size_t object = 0u; object < objects; object += 1u)
        {

            // objects is at most 2 * 0x3FFFFFFF, below 2^31, so the index fits the unsigned int.
            parent[object] = (unsigned int)object;
            local[object] = -1;
        }
        // Union the two ends of every pair. After objects sit past before_count in the same forest.
        for (unsigned int pair = 0u; pair < args->pairs; pair += 1u)
        {
            const unsigned int left = matching_root(parent, args->before[pair]);
            const unsigned int right = matching_root(parent, args->before_count + args->after[pair]);
            if (left != right)
            {
                parent[right] = left;
            }
        }

        // Group the pairs by component with a counting sort on the component's root: count, prefix
        // sum into starts, then scatter into members.
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
