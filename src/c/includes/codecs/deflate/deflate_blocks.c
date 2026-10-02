// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// deflate_blocks.c: runs, trees and writing the blocks
#include "deflate_internal.h"

static const unsigned char deflate_length_extra[DEFLATE_LENGTH_SLOTS] = {
    0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 1u, 1u, 1u, 1u, 2u, 2u, 2u, 2u, 3u, 3u, 3u, 3u, 4u, 4u, 4u, 4u, 5u, 5u, 5u, 5u, 0u};

static const unsigned char deflate_distance_extra[DEFLATE_DISTANCE_CODES] = {
    0u, 0u, 0u, 0u, 1u, 1u, 2u, 2u,  3u,  3u,  4u,  4u,  5u,  5u,  6u,
    6u, 7u, 7u, 8u, 8u, 9u, 9u, 10u, 10u, 11u, 11u, 12u, 12u, 13u, 13u};

static const unsigned char deflate_code_length_order[DEFLATE_CODE_LENGTH_CODES] = {
    16u, 17u, 18u, 0u, 8u, 7u, 9u, 6u, 10u, 5u, 11u, 4u, 12u, 3u, 13u, 2u, 14u, 1u, 15u};

static void deflate_run(DeflateTrees *trees, unsigned int symbol, unsigned int extra)
{
    // a code length symbol is below 19 and its extra value below 128, each fits in an unsigned char
    trees->run_symbols[trees->run_count] = (unsigned char)symbol;
    // the extra value is below 128 and fits in an unsigned char
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
    if (!deflate_lengths(literal_frequency, DEFLATE_LITERAL_CODES, DEFLATE_CODE_BITS, trees->lengths) ||
        !deflate_lengths(distance_frequency, DEFLATE_DISTANCE_CODES, DEFLATE_CODE_BITS,
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
    while ((trees->code_length_count > 4u) &&
           (trees->code_length_lengths[deflate_code_length_order[trees->code_length_count - 1u]] == 0u))
    {
        trees->code_length_count -= 1u;
    }
    return 1;
}

static unsigned long long deflate_symbol_bits(const DeflateToken *tokens, unsigned long long count,
                                              const DeflateTrees *trees)
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
        bits += trees->lengths[DEFLATE_END_OF_BLOCK + 1u + length_slot] + deflate_length_extra[length_slot] +
                trees->lengths[DEFLATE_LITERAL_CODES + distance_slot] + deflate_distance_extra[distance_slot];
    }
    return bits;
}

static unsigned long long deflate_dynamic_bits(const DeflateToken *tokens, unsigned long long count,
                                               const DeflateTrees *trees)
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
        if (writer->written == writer->capacity)
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
        deflate_put(writer, tokens[token].value - deflate_distance_base[distance_slot],
                    deflate_distance_extra[distance_slot]);
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
        const unsigned long long take =
            ((in_bytes - at) < DEFLATE_STORED_CEILING) ? (in_bytes - at) : DEFLATE_STORED_CEILING;
        const unsigned int last = ((at + take) == in_bytes) ? 1u : 0u;
        deflate_put(writer, last, 1u);
        deflate_put(writer, 0u, 2u);
        deflate_align(writer);
        // a stored block's length is at most 65535, which fits in an unsigned int
        const unsigned int length = (unsigned int)take;
        deflate_put(writer, length, 16u);
        deflate_put(writer, length ^ 0xFFFFu, 16u);
        if ((writer->capacity - writer->written) < take)
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
        return ENGINE_BYTES_ERROR;
    }
    const unsigned long long in_bytes = request->in_bytes;
    const unsigned long long range = (in_bytes < DEFLATE_KEYS) ? in_bytes : DEFLATE_KEYS;
    unsigned int key_bits = 0u;
    while ((1ull << key_bits) < range)
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
    int ok =
        (matcher.heads != NULL) && (matcher.previous != NULL) && (tokens != NULL) && (trees != NULL) && (fixed != NULL);
    const unsigned long long count = ok ? deflate_parse(&matcher, tokens) : 0ull;
    ok = ok && deflate_trees(tokens, count, trees);
    if (ok)
    {
        deflate_fixed_trees(fixed);
    }
    const unsigned long long dynamic_bytes = ok ? ((deflate_dynamic_bits(tokens, count, trees) + 7ull) / 8ull) : 0ull;
    const unsigned long long fixed_bytes =
        ok ? ((3ull + deflate_symbol_bits(tokens, count, fixed) + 7ull) / 8ull) : 0ull;
    const unsigned long long stored_bytes = deflate_raw_bound(in_bytes);
    const int use_fixed = (fixed_bytes < dynamic_bytes);
    const unsigned long long coded_bytes = use_fixed ? fixed_bytes : dynamic_bytes;
    const int stored = (stored_bytes < coded_bytes);
    const unsigned long long chosen = stored ? stored_bytes : coded_bytes;
    ok = ok && (chosen <= request->out_capacity);
    DeflateWriter writer = {request->out, request->out_capacity, 0ull, 0ull, 0u, 0};
    if (ok && stored)
    {
        deflate_write_stored(&writer, request->in, in_bytes);
    }
    else if (ok && use_fixed)
    {
        deflate_write_fixed(&writer, tokens, count, fixed);
    }
    else if (ok)
    {
        deflate_write_dynamic(&writer, tokens, count, trees);
    }
    ok = ok && (writer.overflow == 0) && (writer.written == chosen);
    free(matcher.heads);
    free(matcher.previous);
    free(tokens);
    free(trees);
    free(fixed);
    // the written count is at most the caller's capacity, a size in memory, and fits a long long
    return ok ? (long long)writer.written : ENGINE_BYTES_ERROR;
}
