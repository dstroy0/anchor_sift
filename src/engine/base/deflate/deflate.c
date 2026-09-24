// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "deflate.h"

#include <stdlib.h>
#include <string.h>

#define DEFLATE_WINDOW 32768ull
#define DEFLATE_MATCH_FLOOR 3ull
#define DEFLATE_MATCH_CEILING 258ull
#define DEFLATE_STORED_CEILING 65535ull
#define DEFLATE_STORED_FRAME 5ull
#define DEFLATE_KEYS (1ull << 24u)
#define DEFLATE_LITERAL_CODES 286u
#define DEFLATE_DISTANCE_CODES 30u
#define DEFLATE_CODE_LENGTH_CODES 19u
#define DEFLATE_END_OF_BLOCK 256u
#define DEFLATE_CODE_BITS 15u
#define DEFLATE_CODE_LENGTH_BITS 7u
#define DEFLATE_LENGTH_SLOTS 29u

typedef struct
{
    unsigned short length;
    unsigned short value;
} DeflateToken;

typedef struct
{
    unsigned long long weight;
    unsigned int leaf;
    unsigned int left;
    unsigned int right;
} DeflateNode;

typedef struct
{
    const unsigned char *in;
    unsigned long long in_bytes;
    unsigned long long *heads;
    unsigned long long *previous;
    unsigned long long mask;
    unsigned int key_bits;
} DeflateMatcher;

typedef struct
{
    unsigned char *out;
    unsigned long long room;
    unsigned long long written;
    unsigned long long bits;
    unsigned int count;
    int overflow;
} DeflateWriter;

typedef struct
{
    unsigned char lengths[DEFLATE_LITERAL_CODES + DEFLATE_DISTANCE_CODES];
    unsigned int codes[DEFLATE_LITERAL_CODES + DEFLATE_DISTANCE_CODES];
    unsigned char code_length_lengths[DEFLATE_CODE_LENGTH_CODES];
    unsigned int code_length_codes[DEFLATE_CODE_LENGTH_CODES];
    unsigned char run_symbols[DEFLATE_LITERAL_CODES + DEFLATE_DISTANCE_CODES];
    unsigned char run_extras[DEFLATE_LITERAL_CODES + DEFLATE_DISTANCE_CODES];
    unsigned int run_count;
    unsigned int literal_count;
    unsigned int distance_count;
    unsigned int code_length_count;
} DeflateTrees;

static const unsigned short deflate_length_base[DEFLATE_LENGTH_SLOTS] = {
    3u, 4u, 5u, 6u, 7u, 8u, 9u, 10u, 11u, 13u, 15u, 17u, 19u, 23u, 27u,
    31u, 35u, 43u, 51u, 59u, 67u, 83u, 99u, 115u, 131u, 163u, 195u, 227u, 258u};

static const unsigned char deflate_length_extra[DEFLATE_LENGTH_SLOTS] = {0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 1u, 1u,
                                                                         1u, 1u, 2u, 2u, 2u, 2u, 3u, 3u, 3u, 3u,
                                                                         4u, 4u, 4u, 4u, 5u, 5u, 5u, 5u, 0u};

static const unsigned short deflate_distance_base[DEFLATE_DISTANCE_CODES] = {
    1u, 2u, 3u, 4u, 5u, 7u, 9u, 13u, 17u, 25u, 33u, 49u, 65u, 97u, 129u,
    193u, 257u, 385u, 513u, 769u, 1025u, 1537u, 2049u, 3073u, 4097u, 6145u, 8193u, 12289u, 16385u, 24577u};

static const unsigned char deflate_distance_extra[DEFLATE_DISTANCE_CODES] = {
    0u, 0u, 0u, 0u, 1u, 1u, 2u, 2u, 3u, 3u, 4u, 4u, 5u, 5u, 6u, 6u, 7u, 7u, 8u, 8u, 9u, 9u, 10u, 10u, 11u, 11u, 12u, 12u, 13u, 13u};

static const unsigned char deflate_code_length_order[DEFLATE_CODE_LENGTH_CODES] = {16u, 17u, 18u, 0u, 8u,  7u, 9u,
                                                                                   6u,  10u, 5u,  11u, 4u, 12u, 3u,
                                                                                   13u, 2u,  14u, 1u,  15u};

static unsigned int deflate_length_slot(unsigned int length)
{
    unsigned int slot = DEFLATE_LENGTH_SLOTS - 1u;
    while (deflate_length_base[slot] > length)
    {
        slot -= 1u;
    }
    return slot;
}

static unsigned int deflate_distance_slot(unsigned int distance)
{
    unsigned int slot = DEFLATE_DISTANCE_CODES - 1u;
    while (deflate_distance_base[slot] > distance)
    {
        slot -= 1u;
    }
    return slot;
}

static unsigned long long deflate_key(const DeflateMatcher *matcher, unsigned long long at)
{
    const unsigned long long key = ((unsigned long long)matcher->in[at] << 16u)
                                 | ((unsigned long long)matcher->in[at + 1ull] << 8u) | matcher->in[at + 2ull];
    unsigned long long folded = 0ull;
    for (unsigned long long rest = key; rest != 0ull; rest >>= matcher->key_bits)
    {
        folded ^= rest & matcher->mask;
    }
    return folded;
}

static void deflate_insert(DeflateMatcher *matcher, unsigned long long at)
{
    if ((matcher->in_bytes - at) < DEFLATE_MATCH_FLOOR)
    {
        return;
    }
    const unsigned long long slot = deflate_key(matcher, at);
    matcher->previous[at] = matcher->heads[slot];
    matcher->heads[slot] = at + 1ull;
}

static unsigned long long deflate_find(const DeflateMatcher *matcher, unsigned long long at, unsigned long long *distance)
{
    *distance = 0ull;
    if ((matcher->in_bytes - at) < DEFLATE_MATCH_FLOOR)
    {
        return 0ull;
    }
    const unsigned long long limit = ((matcher->in_bytes - at) < DEFLATE_MATCH_CEILING) ? (matcher->in_bytes - at)
                                                                                        : DEFLATE_MATCH_CEILING;
    unsigned long long best = 0ull;
    unsigned long long candidate = matcher->heads[deflate_key(matcher, at)];
    while (candidate != 0ull)
    {
        const unsigned long long earlier = candidate - 1ull;
        if ((at - earlier) > DEFLATE_WINDOW)
        {
            break;
        }
        unsigned long long length = 0ull;
        while ((length < limit) && (matcher->in[earlier + length] == matcher->in[at + length]))
        {
            length += 1ull;
        }
        if (length > best)
        {
            best = length;
            *distance = at - earlier;
            if (best == limit)
            {
                break;
            }
        }
        candidate = matcher->previous[earlier];
    }
    return (best >= DEFLATE_MATCH_FLOOR) ? best : 0ull;
}

static void deflate_token(DeflateToken *tokens, unsigned long long *count, unsigned long long length, unsigned long long value)
{
    // a match length is at most 258 and a distance at most 32768, each held whole in an unsigned short
    tokens[*count].length = (unsigned short)length;
    // a literal byte or a distance of at most 32768 is held whole in an unsigned short
    tokens[*count].value = (unsigned short)value;
    *count += 1ull;
}

static unsigned long long deflate_parse(DeflateMatcher *matcher, DeflateToken *tokens)
{
    unsigned long long count = 0ull;
    unsigned long long at = 0ull;
    while (at < matcher->in_bytes)
    {
        unsigned long long distance = 0ull;
        const unsigned long long length = deflate_find(matcher, at, &distance);
        if (length == 0ull)
        {
            deflate_token(tokens, &count, 0ull, matcher->in[at]);
            deflate_insert(matcher, at);
            at += 1ull;
            continue;
        }
        deflate_insert(matcher, at);
        unsigned long long later_distance = 0ull;
        const unsigned long long later = ((at + 1ull) < matcher->in_bytes) ? deflate_find(matcher, at + 1ull, &later_distance)
                                                                         : 0ull;
        if (later > length)
        {
            deflate_token(tokens, &count, 0ull, matcher->in[at]);
            at += 1ull;
            continue;
        }
        deflate_token(tokens, &count, length, distance);
        for (unsigned long long step = 1ull; step < length; step += 1ull)
        {
            deflate_insert(matcher, at + step);
        }
        at += length;
    }
    return count;
}

static unsigned int deflate_count_leaves(const DeflateNode *nodes, unsigned int node, unsigned char *lengths)
{
    if (nodes[node].left == nodes[node].right)
    {
        lengths[nodes[node].leaf] += 1u;
        return 1u;
    }
    return deflate_count_leaves(nodes, nodes[node].left, lengths) + deflate_count_leaves(nodes, nodes[node].right, lengths);
}

static int deflate_lengths(const unsigned long long *frequency, unsigned int count, unsigned int limit, unsigned char *lengths)
{
    memset(lengths, 0, count);
    unsigned int used = 0u;
    unsigned int only = 0u;
    for (unsigned int symbol = 0u; symbol < count; symbol += 1u)
    {
        used += (frequency[symbol] != 0ull) ? 1u : 0u;
        only = (frequency[symbol] != 0ull) ? symbol : only;
    }
    if (used < 2u)
    {
        lengths[only] = 1u;
        lengths[(only == 0u) ? 1u : 0u] = 1u;
        return 1;
    }
    const unsigned int room = limit * 2u * used;
    DeflateNode *const nodes = (DeflateNode *)malloc(sizeof(DeflateNode) * room);
    unsigned int *const leaves = (unsigned int *)malloc(sizeof(unsigned int) * used);
    unsigned int *const list = (unsigned int *)malloc(sizeof(unsigned int) * 2u * used);
    unsigned int *const next = (unsigned int *)malloc(sizeof(unsigned int) * 2u * used);
    if ((nodes == NULL) || (leaves == NULL) || (list == NULL) || (next == NULL))
    {
        free(nodes);
        free(leaves);
        free(list);
        free(next);
        return 0;
    }
    unsigned int made = 0u;
    for (unsigned int symbol = 0u; symbol < count; symbol += 1u)
    {
        if (frequency[symbol] == 0ull)
        {
            continue;
        }
        unsigned int place = made;
        while ((place > 0u) && (nodes[leaves[place - 1u]].weight > frequency[symbol]))
        {
            leaves[place] = leaves[place - 1u];
            place -= 1u;
        }
        nodes[made].weight = frequency[symbol];
        nodes[made].leaf = symbol;
        nodes[made].left = 0u;
        nodes[made].right = 0u;
        leaves[place] = made;
        made += 1u;
    }
    unsigned int listed = used;
    memcpy(list, leaves, sizeof(unsigned int) * used);
    for (unsigned int level = 1u; level < limit; level += 1u)
    {
        const unsigned int packages = listed / 2u;
        const unsigned int package_first = made;
        for (unsigned int package = 0u; package < packages; package += 1u)
        {
            nodes[made].weight = nodes[list[2u * package]].weight + nodes[list[(2u * package) + 1u]].weight;
            nodes[made].leaf = 0u;
            nodes[made].left = list[2u * package];
            nodes[made].right = list[(2u * package) + 1u];
            made += 1u;
        }
        unsigned int leaf_at = 0u;
        unsigned int package_at = 0u;
        listed = 0u;
        while ((leaf_at < used) || (package_at < packages))
        {
            const int take_leaf = (package_at == packages)
                               || ((leaf_at < used)
                                   && (nodes[leaves[leaf_at]].weight <= nodes[package_first + package_at].weight));
            next[listed] = take_leaf ? leaves[leaf_at] : (package_first + package_at);
            leaf_at += take_leaf ? 1u : 0u;
            package_at += take_leaf ? 0u : 1u;
            listed += 1u;
        }
        memcpy(list, next, sizeof(unsigned int) * listed);
    }
    for (unsigned int item = 0u; item < ((2u * used) - 2u); item += 1u)
    {
        deflate_count_leaves(nodes, list[item], lengths);
    }
    free(nodes);
    free(leaves);
    free(list);
    free(next);
    return 1;
}

static void deflate_codes(const unsigned char *lengths, unsigned int count, unsigned int *codes)
{
    unsigned int per_length[DEFLATE_CODE_BITS + 1u];
    unsigned int next_code[DEFLATE_CODE_BITS + 1u];
    memset(per_length, 0, sizeof(per_length));
    for (unsigned int symbol = 0u; symbol < count; symbol += 1u)
    {
        per_length[lengths[symbol]] += 1u;
    }
    per_length[0] = 0u;
    unsigned int code = 0u;
    next_code[0] = 0u;
    for (unsigned int length = 1u; length <= DEFLATE_CODE_BITS; length += 1u)
    {
        code = (code + per_length[length - 1u]) << 1u;
        next_code[length] = code;
    }
    for (unsigned int symbol = 0u; symbol < count; symbol += 1u)
    {
        const unsigned int length = lengths[symbol];
        codes[symbol] = 0u;
        if (length == 0u)
        {
            continue;
        }
        const unsigned int canonical = next_code[length];
        next_code[length] += 1u;
        for (unsigned int bit = 0u; bit < length; bit += 1u)
        {
            codes[symbol] |= ((canonical >> bit) & 1u) << (length - 1u - bit);
        }
    }
}

static void deflate_run(DeflateTrees *trees, unsigned int symbol, unsigned int extra)
{
    // a code length symbol is below 19 and its extra value below 128, each held whole in an unsigned char
    trees->run_symbols[trees->run_count] = (unsigned char)symbol;
    // the extra value is below 128 and is held whole in an unsigned char
    trees->run_extras[trees->run_count] = (unsigned char)extra;
    trees->run_count += 1u;
}

static void deflate_runs(DeflateTrees *trees)
{
    const unsigned int total = trees->literal_count + trees->distance_count;
    unsigned char joined[DEFLATE_LITERAL_CODES + DEFLATE_DISTANCE_CODES];
    memcpy(joined, trees->lengths, trees->literal_count);
    memcpy(joined + trees->literal_count, trees->lengths + DEFLATE_LITERAL_CODES, trees->distance_count);
    trees->run_count = 0u;
    unsigned int at = 0u;
    while (at < total)
    {
        const unsigned int value = joined[at];
        unsigned int run = 1u;
        while (((at + run) < total) && (joined[at + run] == value))
        {
            run += 1u;
        }
        unsigned int rest = run;
        if (value == 0u)
        {
            while (rest >= 11u)
            {
                const unsigned int take = (rest < 138u) ? rest : 138u;
                deflate_run(trees, 18u, take - 11u);
                rest -= take;
            }
            if (rest >= 3u)
            {
                deflate_run(trees, 17u, rest - 3u);
                rest = 0u;
            }
        }
        else
        {
            deflate_run(trees, value, 0u);
            rest -= 1u;
            while (rest >= 3u)
            {
                const unsigned int take = (rest < 6u) ? rest : 6u;
                deflate_run(trees, 16u, take - 3u);
                rest -= take;
            }
        }
        while (rest > 0u)
        {
            deflate_run(trees, value, 0u);
            rest -= 1u;
        }
        at += run;
    }
}

static unsigned int deflate_run_extra_bits(unsigned int symbol)
{
    return (symbol == 16u) ? 2u : ((symbol == 17u) ? 3u : ((symbol == 18u) ? 7u : 0u));
}

static int deflate_trees(const DeflateToken *tokens, unsigned long long count, DeflateTrees *trees)
{
    unsigned long long literal_frequency[DEFLATE_LITERAL_CODES];
    unsigned long long distance_frequency[DEFLATE_DISTANCE_CODES];
    unsigned long long code_length_frequency[DEFLATE_CODE_LENGTH_CODES];
    memset(literal_frequency, 0, sizeof(literal_frequency));
    memset(distance_frequency, 0, sizeof(distance_frequency));
    memset(code_length_frequency, 0, sizeof(code_length_frequency));
    for (unsigned long long token = 0ull; token < count; token += 1ull)
    {
        if (tokens[token].length == 0u)
        {
            literal_frequency[tokens[token].value] += 1ull;
            continue;
        }
        literal_frequency[DEFLATE_END_OF_BLOCK + 1u + deflate_length_slot(tokens[token].length)] += 1ull;
        distance_frequency[deflate_distance_slot(tokens[token].value)] += 1ull;
    }
    literal_frequency[DEFLATE_END_OF_BLOCK] += 1ull;
    if (!deflate_lengths(literal_frequency, DEFLATE_LITERAL_CODES, DEFLATE_CODE_BITS, trees->lengths)
        || !deflate_lengths(distance_frequency, DEFLATE_DISTANCE_CODES, DEFLATE_CODE_BITS,
                            trees->lengths + DEFLATE_LITERAL_CODES))
    {
        return 0;
    }
    trees->literal_count = DEFLATE_LITERAL_CODES;
    while ((trees->literal_count > (DEFLATE_END_OF_BLOCK + 1u)) && (trees->lengths[trees->literal_count - 1u] == 0u))
    {
        trees->literal_count -= 1u;
    }
    trees->distance_count = DEFLATE_DISTANCE_CODES;
    while ((trees->distance_count > 1u) && (trees->lengths[DEFLATE_LITERAL_CODES + trees->distance_count - 1u] == 0u))
    {
        trees->distance_count -= 1u;
    }
    deflate_codes(trees->lengths, DEFLATE_LITERAL_CODES, trees->codes);
    deflate_codes(trees->lengths + DEFLATE_LITERAL_CODES, DEFLATE_DISTANCE_CODES, trees->codes + DEFLATE_LITERAL_CODES);
    deflate_runs(trees);
    for (unsigned int run = 0u; run < trees->run_count; run += 1u)
    {
        code_length_frequency[trees->run_symbols[run]] += 1ull;
    }
    if (!deflate_lengths(code_length_frequency, DEFLATE_CODE_LENGTH_CODES, DEFLATE_CODE_LENGTH_BITS,
                         trees->code_length_lengths))
    {
        return 0;
    }
    deflate_codes(trees->code_length_lengths, DEFLATE_CODE_LENGTH_CODES, trees->code_length_codes);
    trees->code_length_count = DEFLATE_CODE_LENGTH_CODES;
    while ((trees->code_length_count > 4u)
           && (trees->code_length_lengths[deflate_code_length_order[trees->code_length_count - 1u]] == 0u))
    {
        trees->code_length_count -= 1u;
    }
    return 1;
}

static unsigned long long deflate_symbol_bits(const DeflateToken *tokens, unsigned long long count, const DeflateTrees *trees)
{
    unsigned long long bits = trees->lengths[DEFLATE_END_OF_BLOCK];
    for (unsigned long long token = 0ull; token < count; token += 1ull)
    {
        if (tokens[token].length == 0u)
        {
            bits += trees->lengths[tokens[token].value];
            continue;
        }
        const unsigned int length_slot = deflate_length_slot(tokens[token].length);
        const unsigned int distance_slot = deflate_distance_slot(tokens[token].value);
        bits += trees->lengths[DEFLATE_END_OF_BLOCK + 1u + length_slot] + deflate_length_extra[length_slot]
              + trees->lengths[DEFLATE_LITERAL_CODES + distance_slot] + deflate_distance_extra[distance_slot];
    }
    return bits;
}

static unsigned long long deflate_dynamic_bits(const DeflateToken *tokens, unsigned long long count, const DeflateTrees *trees)
{
    unsigned long long bits = 3ull + 5ull + 5ull + 4ull + (3ull * trees->code_length_count);
    for (unsigned int run = 0u; run < trees->run_count; run += 1u)
    {
        bits += trees->code_length_lengths[trees->run_symbols[run]] + deflate_run_extra_bits(trees->run_symbols[run]);
    }
    return bits + deflate_symbol_bits(tokens, count, trees);
}

static void deflate_fixed_trees(DeflateTrees *fixed)
{
    memset(fixed, 0, sizeof(*fixed));
    memset(fixed->lengths, 8, 144u);
    memset(fixed->lengths + 144u, 9, 112u);
    memset(fixed->lengths + 256u, 7, 24u);
    memset(fixed->lengths + 280u, 8, DEFLATE_LITERAL_CODES - 280u);
    memset(fixed->lengths + DEFLATE_LITERAL_CODES, 5, DEFLATE_DISTANCE_CODES);
    unsigned char literal_lengths[DEFLATE_LITERAL_CODES + 2u];
    unsigned int literal_codes[DEFLATE_LITERAL_CODES + 2u];
    memcpy(literal_lengths, fixed->lengths, DEFLATE_LITERAL_CODES);
    memset(literal_lengths + DEFLATE_LITERAL_CODES, 8, 2u);
    deflate_codes(literal_lengths, DEFLATE_LITERAL_CODES + 2u, literal_codes);
    memcpy(fixed->codes, literal_codes, sizeof(unsigned int) * DEFLATE_LITERAL_CODES);
    deflate_codes(fixed->lengths + DEFLATE_LITERAL_CODES, DEFLATE_DISTANCE_CODES, fixed->codes + DEFLATE_LITERAL_CODES);
}

static void deflate_put(DeflateWriter *writer, unsigned int value, unsigned int count)
{
    writer->bits |= (unsigned long long)value << writer->count;
    writer->count += count;
    while (writer->count >= 8u)
    {
        if (writer->written == writer->room)
        {
            writer->overflow = 1;
            return;
        }
        // the low byte of the accumulator is taken whole
        writer->out[writer->written] = (unsigned char)(writer->bits & 0xFFull);
        writer->written += 1ull;
        writer->bits >>= 8u;
        writer->count -= 8u;
    }
}

static void deflate_align(DeflateWriter *writer)
{
    if (writer->count != 0u)
    {
        deflate_put(writer, 0u, 8u - writer->count);
    }
}

static void deflate_write_symbols(DeflateWriter *writer, const DeflateToken *tokens, unsigned long long count,
                                  const DeflateTrees *trees)
{
    for (unsigned long long token = 0ull; (token < count) && (writer->overflow == 0); token += 1ull)
    {
        if (tokens[token].length == 0u)
        {
            deflate_put(writer, trees->codes[tokens[token].value], trees->lengths[tokens[token].value]);
            continue;
        }
        const unsigned int length_slot = deflate_length_slot(tokens[token].length);
        const unsigned int distance_slot = deflate_distance_slot(tokens[token].value);
        const unsigned int length_symbol = DEFLATE_END_OF_BLOCK + 1u + length_slot;
        const unsigned int distance_symbol = DEFLATE_LITERAL_CODES + distance_slot;
        deflate_put(writer, trees->codes[length_symbol], trees->lengths[length_symbol]);
        deflate_put(writer, tokens[token].length - deflate_length_base[length_slot], deflate_length_extra[length_slot]);
        deflate_put(writer, trees->codes[distance_symbol], trees->lengths[distance_symbol]);
        deflate_put(writer, tokens[token].value - deflate_distance_base[distance_slot], deflate_distance_extra[distance_slot]);
    }
    deflate_put(writer, trees->codes[DEFLATE_END_OF_BLOCK], trees->lengths[DEFLATE_END_OF_BLOCK]);
    deflate_align(writer);
}

static void deflate_write_dynamic(DeflateWriter *writer, const DeflateToken *tokens, unsigned long long count,
                                  const DeflateTrees *trees)
{
    deflate_put(writer, 1u, 1u);
    deflate_put(writer, 2u, 2u);
    deflate_put(writer, trees->literal_count - 257u, 5u);
    deflate_put(writer, trees->distance_count - 1u, 5u);
    deflate_put(writer, trees->code_length_count - 4u, 4u);
    for (unsigned int slot = 0u; slot < trees->code_length_count; slot += 1u)
    {
        deflate_put(writer, trees->code_length_lengths[deflate_code_length_order[slot]], 3u);
    }
    for (unsigned int run = 0u; run < trees->run_count; run += 1u)
    {
        const unsigned int symbol = trees->run_symbols[run];
        deflate_put(writer, trees->code_length_codes[symbol], trees->code_length_lengths[symbol]);
        deflate_put(writer, trees->run_extras[run], deflate_run_extra_bits(symbol));
    }
    deflate_write_symbols(writer, tokens, count, trees);
}

static void deflate_write_fixed(DeflateWriter *writer, const DeflateToken *tokens, unsigned long long count,
                                const DeflateTrees *fixed)
{
    deflate_put(writer, 1u, 1u);
    deflate_put(writer, 1u, 2u);
    deflate_write_symbols(writer, tokens, count, fixed);
}

static void deflate_write_stored(DeflateWriter *writer, const unsigned char *in, unsigned long long in_bytes)
{
    unsigned long long at = 0ull;
    do
    {
        const unsigned long long take = ((in_bytes - at) < DEFLATE_STORED_CEILING) ? (in_bytes - at) : DEFLATE_STORED_CEILING;
        const unsigned int last = ((at + take) == in_bytes) ? 1u : 0u;
        deflate_put(writer, last, 1u);
        deflate_put(writer, 0u, 2u);
        deflate_align(writer);
        // a stored block's length is at most 65535, held whole in an unsigned int
        const unsigned int length = (unsigned int)take;
        deflate_put(writer, length, 16u);
        deflate_put(writer, length ^ 0xFFFFu, 16u);
        if ((writer->room - writer->written) < take)
        {
            writer->overflow = 1;
            return;
        }
        if (take != 0ull)
        {
            memcpy(writer->out + writer->written, in + at, (size_t)take);
        }
        writer->written += take;
        at += take;
    } while ((at < in_bytes) && (writer->overflow == 0));
}

unsigned long long deflate_raw_bound(unsigned long long in_bytes)
{
    const unsigned long long blocks = (in_bytes == 0ull) ? 1ull : (((in_bytes - 1ull) / DEFLATE_STORED_CEILING) + 1ull);
    return in_bytes + (DEFLATE_STORED_FRAME * blocks);
}

long long deflate_raw_encode(const EngineBytesRequest *request)
{
    if ((request == NULL) || ((request->in == NULL) && (request->in_bytes != 0ull)) || (request->out == NULL))
    {
        return ENGINE_BYTES_REFUSED;
    }
    const unsigned long long in_bytes = request->in_bytes;
    const unsigned long long reach = (in_bytes < DEFLATE_KEYS) ? in_bytes : DEFLATE_KEYS;
    unsigned int key_bits = 0u;
    while ((1ull << key_bits) < reach)
    {
        key_bits += 1u;
    }
    const unsigned long long slots = 1ull << key_bits;
    DeflateMatcher matcher;
    matcher.in = request->in;
    matcher.in_bytes = in_bytes;
    matcher.heads = (unsigned long long *)calloc((size_t)slots, sizeof(unsigned long long));
    matcher.previous = (unsigned long long *)calloc((size_t)in_bytes + 1u, sizeof(unsigned long long));
    matcher.mask = slots - 1ull;
    matcher.key_bits = (key_bits == 0u) ? 1u : key_bits;
    DeflateToken *const tokens = (DeflateToken *)malloc(((size_t)in_bytes + 1u) * sizeof(DeflateToken));
    DeflateTrees *const trees = (DeflateTrees *)calloc(1u, sizeof(DeflateTrees));
    DeflateTrees *const fixed = (DeflateTrees *)calloc(1u, sizeof(DeflateTrees));
    int good = (matcher.heads != NULL) && (matcher.previous != NULL) && (tokens != NULL) && (trees != NULL)
            && (fixed != NULL);
    const unsigned long long count = good ? deflate_parse(&matcher, tokens) : 0ull;
    good = good && deflate_trees(tokens, count, trees);
    if (good)
    {
        deflate_fixed_trees(fixed);
    }
    const unsigned long long dynamic_bytes = good ? ((deflate_dynamic_bits(tokens, count, trees) + 7ull) / 8ull) : 0ull;
    const unsigned long long fixed_bytes = good ? ((3ull + deflate_symbol_bits(tokens, count, fixed) + 7ull) / 8ull) : 0ull;
    const unsigned long long stored_bytes = deflate_raw_bound(in_bytes);
    const int use_fixed = (fixed_bytes < dynamic_bytes);
    const unsigned long long coded_bytes = use_fixed ? fixed_bytes : dynamic_bytes;
    const int stored = (stored_bytes < coded_bytes);
    const unsigned long long chosen = stored ? stored_bytes : coded_bytes;
    good = good && (chosen <= request->out_room);
    DeflateWriter writer = {request->out, request->out_room, 0ull, 0ull, 0u, 0};
    if (good && stored)
    {
        deflate_write_stored(&writer, request->in, in_bytes);
    }
    else if (good && use_fixed)
    {
        deflate_write_fixed(&writer, tokens, count, fixed);
    }
    else if (good)
    {
        deflate_write_dynamic(&writer, tokens, count, trees);
    }
    good = good && (writer.overflow == 0) && (writer.written == chosen);
    free(matcher.heads);
    free(matcher.previous);
    free(tokens);
    free(trees);
    free(fixed);
    // the written count is at most the caller's room, a size in memory, and fits a long long
    return good ? (long long)writer.written : ENGINE_BYTES_REFUSED;
}
