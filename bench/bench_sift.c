// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "impensa_ancorae_acus/impensa_ancorae_acus.h"

#include "mmgr_sha256.h"

#include <math.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>

#define CORPUS_BYTES 2048u

#define NEEDLE_SAMPLES 64u

static const char s_english[] =
    "the quick brown fox jumps over the lazy dog while the quiet queen quietly questioned whether "
    "the quality of the quotation was quite equal to the requirements of the inquiry. she thought "
    "about the matter for some time and then decided that the answer was probably yes, although "
    "there were several other considerations that might reasonably be taken into account before "
    "any final judgement could be reached on a question of that particular kind. the morning was "
    "bright and the air was cold, and the road ahead of them ran straight for a long distance "
    "before turning sharply to the left and disappearing behind a low hill covered in heather. "
    "they walked without speaking for perhaps half an hour, each of them thinking about something "
    "different, until the sound of running water reached them from somewhere ahead and below. "
    "the river was wider than either of them had expected and the crossing took longer than it "
    "should have done, partly because the stones were slippery and partly because neither of them "
    "wanted to admit to the other that they were frightened of falling. afterwards they sat on the "
    "far bank and dried their feet in the sun and agreed that it had not been so bad after all. "
    "later that evening the weather turned and a thin rain began to fall, first in single drops "
    "that marked the dust and then steadily. That within a quarter of an hour the whole valley "
    "was grey and the far side of it invisible. they sheltered under an overhanging rock and "
    "watched the water gather in the hollows and run away downhill in a hundred small channels, "
    "each one finding its own way among the stones without any apparent difficulty. it occurred to "
    "him that this was how most problems eventually resolved themselves, given enough time and a "
    "sufficient quantity of water, and he said as much aloud. she laughed and said that was the "
    "sort of remark that sounded wiser than it was, and he had to agree that she was probably "
    "right about that as well. by the time the rain stopped the light was almost gone and they "
    "made camp where they stood. the fire took a long "
    "while to catch because everything was wet, and when it did catch it smoked badly and gave "
    "very little heat, but it was something to sit beside and they were both glad of it. in the "
    "morning the sky had cleared completely and the grass was heavy with water that soaked their "
    "boots within the first few steps. neither of them mentioned the conversation of the previous "
    "evening, though both remembered it, and they walked down toward the village in a silence "
    "that was comfortable. the bakery was already open when they arrived and "
    "the smell of it reached them from a considerable distance up the road, which improved their "
    "mood more than anything either of them could have said. ";

static uint8_t s_english_corpus[CORPUS_BYTES];
static uint8_t s_structured_corpus[CORPUS_BYTES];
static uint8_t s_uniform_corpus[CORPUS_BYTES];
static uint8_t s_periodic_corpus[CORPUS_BYTES];

static uint8_t s_flat_corpus[CORPUS_BYTES];

static const char s_structured[] =
    "static void mmgr_walk_rows(const uint8_t *bytes, size_t length, uint32_t *counts)\n"
    "{\n"
    "    for (size_t index = 0u; index < length; index++)\n"
    "    {\n"
    "        counts[bytes[index]]++;\n"
    "    }\n"
    "}\n"
    "\n"
    "static uint32_t mmgr_pick_lowest(const uint8_t *needle, size_t length)\n"
    "{\n"
    "    uint32_t best = 0u;\n"
    "    unsigned best_cost = 256u;\n"
    "    for (size_t index = 0u; index < length; index++)\n"
    "    {\n"
    "        const unsigned cost = table[needle[index]];\n"
    "        if (cost < best_cost)\n"
    "        {\n"
    "            best_cost = cost;\n"
    "            best = (uint32_t)index;\n"
    "        }\n"
    "    }\n"
    "    return best;\n"
    "}\n"
    "\n"
    "embed_bool mmgr_sift_span(const SiftCfg *args)\n"
    "{\n"
    "    MMGR_ASSERT(args->bytes != NULL, \"a span with no bytes\");\n"
    "    if (args->length < args->needle_len)\n"
    "    {\n"
    "        return EMBED_FALSE;\n"
    "    }\n"
    "    const size_t anchor = mmgr_pick_lowest(args->needle, args->needle_len);\n"
    "    for (size_t start = 0u; (start + args->needle_len) <= args->length; start++)\n"
    "    {\n"
    "        if (args->bytes[start + anchor] != args->needle[anchor])\n"
    "        {\n"
    "            continue;\n"
    "        }\n"
    "        if (mmgr_span_equal(&args->bytes[start], args->needle, args->needle_len))\n"
    "        {\n"
    "            return EMBED_TRUE;\n"
    "        }\n"
    "    }\n"
    "    return EMBED_FALSE;\n"
    "}\n"
    "\n"
    "static uint32_t mmgr_fold_word(uint32_t word, uint32_t mask, unsigned places)\n"
    "{\n"
    "    const uint32_t high = (word >> places) & mask;\n"
    "    const uint32_t low = (word << (32u - places)) & ~mask;\n"
    "    return high | low;\n"
    "}\n";

static size_t fill_from_text(uint8_t *into, const char *text, size_t length)
{
    const size_t text_bytes = strlen(text);
    const size_t usable = (text_bytes < length) ? text_bytes : length;

    for (size_t index = 0u; index < usable; index++)
    {
        into[index] = (uint8_t)text[index];
    }
    return usable;
}

#define RECORD_BYTES 16u

static size_t fill_periodic(uint8_t *into, size_t length)
{
    static const char hex[] = "0123456789abcdef";
    const size_t records = length / RECORD_BYTES;

    for (size_t record = 0u; record < records; record++)
    {
        uint8_t *const at = &into[record * RECORD_BYTES];
        const size_t counter = record * 2654435761u;

        at[0] = (uint8_t)hex[(counter >> 12) & 0xFu];
        at[1] = (uint8_t)hex[(counter >> 8) & 0xFu];
        at[2] = (uint8_t)hex[(counter >> 4) & 0xFu];
        at[3] = (uint8_t)hex[counter & 0xFu];
        at[4] = (uint8_t)',';
        for (unsigned letter = 0u; letter < 6u; letter++)
        {
            at[5u + letter] = (uint8_t)('a' + (int)((counter >> (letter * 3u)) % 26u));
        }
        at[11] = (uint8_t)',';
        at[12] = (uint8_t)('0' + (int)((counter / 100u) % 10u));
        at[13] = (uint8_t)('0' + (int)((counter / 10u) % 10u));
        at[14] = (uint8_t)('0' + (int)(counter % 10u));
        at[15] = (uint8_t)'\n';
    }
    return records * RECORD_BYTES;
}

static void fill_uniform(uint8_t *into, size_t length)
{
    uint8_t counter[8];
    uint8_t digest[MMGR_SHA256_BYTES];
    size_t written = 0u;
    uint64_t block = 0u;

    while (written < length)
    {
        for (unsigned index = 0u; index < 8u; index++)
        {
            counter[index] = (uint8_t)((block >> (56u - (index * 8u))) & 0xFFu);
        }
        mmgr_sha256(counter, sizeof counter, digest);

        for (unsigned index = 0u; (index < MMGR_SHA256_BYTES) && (written < length); index++)
        {
            into[written] = digest[index];
            written++;
        }
        block++;
    }
}

static uint32_t table_fingerprint(void)
{
    uint32_t running = 2166136261u;

    for (unsigned byte = 0u; byte < 256u; byte++)
    {
        running ^= (uint32_t)EMBED_CALL(ancorae.impensa, AncoraeCfg, .byte = (uint8_t)byte);
        running *= 16777619u;
    }
    return running;
}

static void histogram(const uint8_t *corpus, size_t length, uint32_t *counts)
{
    for (unsigned byte = 0u; byte < 256u; byte++)
    {
        counts[byte] = 0u;
    }
    for (size_t index = 0u; index < length; index++)
    {
        counts[corpus[index]]++;
    }
}

typedef enum
{
    ANCHOR_BY_TABLE = 0,
    ANCHOR_BY_RANDOM = 1,
    ANCHOR_BY_MAXIMUM_ENTROPY = 2
} AnchorPolicy;

static unsigned s_random_cost[256];

static void fill_random_costs(void)
{
    uint8_t digest[MMGR_SHA256_BYTES];
    uint8_t counter[8];
    unsigned drawn = MMGR_SHA256_BYTES;
    uint64_t block = 0u;

    for (unsigned slot = 0u; slot < 256u; slot++)
    {
        s_random_cost[slot] = slot;
    }

    for (unsigned slot = 255u; slot > 0u; slot--)
    {
        if (drawn == MMGR_SHA256_BYTES)
        {
            for (unsigned index = 0u; index < 8u; index++)
            {
                counter[index] = (uint8_t)((block >> (56u - (index * 8u))) & 0xFFu);
            }
            mmgr_sha256(counter, sizeof counter, digest);
            drawn = 0u;
            block++;
        }

        const unsigned pick = (unsigned)digest[drawn] % (slot + 1u);
        const unsigned held = s_random_cost[slot];

        drawn++;
        s_random_cost[slot] = s_random_cost[pick];
        s_random_cost[pick] = held;
    }
}

static unsigned anchor_cost(uint8_t byte, AnchorPolicy policy)
{
    switch (policy)
    {
    case ANCHOR_BY_RANDOM:
    {
        return s_random_cost[byte];
    }
    case ANCHOR_BY_MAXIMUM_ENTROPY:
    {
        return 0u;
    }
    case ANCHOR_BY_TABLE:
    default:
    {
        return (unsigned)EMBED_CALL(ancorae.impensa, AncoraeCfg, .byte = byte);
    }
    }
}

static const char *policy_name(AnchorPolicy policy)
{
    switch (policy)
    {
    case ANCHOR_BY_RANDOM:
    {
        return "random";
    }
    case ANCHOR_BY_MAXIMUM_ENTROPY:
    {
        return "maxent";
    }
    case ANCHOR_BY_TABLE:
    default:
    {
        return "table";
    }
    }
}

static size_t cheapest_offset(const uint8_t *needle, size_t length, size_t skip, AnchorPolicy policy)
{
    size_t best = length;
    unsigned best_cost = 256u;

    for (size_t index = 0u; index < length; index++)
    {
        if (index == skip)
        {
            continue;
        }

        const unsigned cost = anchor_cost(needle[index], policy);

        if (cost < best_cost)
        {
            best_cost = cost;
            best = index;
        }
    }
    return best;
}

static uint32_t candidates(const uint8_t *corpus, size_t length, uint8_t first, size_t first_at, uint8_t second,
                           size_t second_at, size_t needle_len)
{
    uint32_t surviving = 0u;

    for (size_t start = 0u; (start + needle_len) <= length; start++)
    {
        if (corpus[start + first_at] != first)
        {
            continue;
        }
        if ((second_at != (size_t)-1) && (corpus[start + second_at] != second))
        {
            continue;
        }
        surviving++;
    }
    return surviving;
}

#define CASCADE_MAX 6u

static unsigned pick_anchors(const uint8_t *needle, size_t needle_len, AnchorPolicy policy, size_t *offsets,
                             unsigned count)
{
    unsigned taken = 0u;

    while (taken < count)
    {
        size_t best = needle_len;
        unsigned best_cost = 256u;

        for (size_t index = 0u; index < needle_len; index++)
        {
            unsigned already = 0u;

            for (unsigned seen = 0u; seen < taken; seen++)
            {
                if (offsets[seen] == index)
                {
                    already = 1u;
                }
            }
            if (already != 0u)
            {
                continue;
            }

            const unsigned cost = anchor_cost(needle[index], policy);

            if (cost < best_cost)
            {
                best_cost = cost;
                best = index;
            }
        }
        if (best == needle_len)
        {
            break;
        }
        offsets[taken] = best;
        taken++;
    }
    return taken;
}

static uint32_t candidates_n(const uint8_t *corpus, size_t length, const uint8_t *needle, const size_t *offsets,
                             unsigned count, size_t needle_len)
{
    uint32_t surviving = 0u;

    for (size_t start = 0u; (start + needle_len) <= length; start++)
    {
        unsigned matched = 0u;

        while ((matched < count) && (corpus[start + offsets[matched]] == needle[offsets[matched]]))
        {
            matched++;
        }
        if (matched == count)
        {
            surviving++;
        }
    }
    return surviving;
}

static void report_cascade(const char *name, const uint8_t *corpus, size_t corpus_len, size_t needle_len,
                           AnchorPolicy policy, uint32_t stamp)
{
    if (needle_len >= (corpus_len / 4u))
    {
        return;
    }

    uint32_t counts[256];
    histogram(corpus, corpus_len, counts);

    const size_t step = (corpus_len - needle_len) / NEEDLE_SAMPLES;

    for (unsigned count = 1u; count <= CASCADE_MAX; count++)
    {
        double observed = 0.0;
        double predicted = 0.0;
        double squares = 0.0;
        unsigned samples = 0u;

        for (size_t sample = 0u; sample < NEEDLE_SAMPLES; sample++)
        {
            const uint8_t *const needle = &corpus[sample * step];
            size_t offsets[CASCADE_MAX];
            const unsigned taken = pick_anchors(needle, needle_len, policy, offsets, count);

            if (taken < count)
            {
                continue;
            }

            double rate = 1.0;

            for (unsigned index = 0u; index < taken; index++)
            {
                rate *= (double)counts[needle[offsets[index]]] / (double)corpus_len;
            }

            const double excess = (double)candidates_n(corpus, corpus_len, needle, offsets, count, needle_len) - 1.0;

            observed += excess;
            squares += excess * excess;
            predicted += (double)(corpus_len - needle_len + 1u) * rate;
            samples++;
        }

        if (samples == 0u)
        {
            continue;
        }

        const double total = (double)samples;
        const double mean = observed / total;
        const double expect = predicted / total;
        const double variance = (total > 1.0) ? ((squares - (total * mean * mean)) / (total - 1.0)) : 0.0;
        const double error = (variance > 0.0) ? (sqrt(variance) / sqrt(total)) : 0.0;

        printf("ancorae_cascade,%08x,%s,%s,%u,%u,%u,%u,%.3f,%.4f,%.2f,%.1f\n", stamp, name, policy_name(policy),
               (unsigned)needle_len, count, (unsigned)corpus_len, samples, mean, expect,
               (expect > 0.0) ? (mean / expect) : 0.0,
               (error > 0.0) ? ((mean - expect) / error) : 0.0);
    }
}

static uint32_t refused_occurrences(const uint8_t *corpus, size_t length, const uint8_t *needle, size_t needle_len,
                                    const size_t *offsets, unsigned count, uint32_t *found)
{
    uint32_t refused = 0u;
    uint32_t occurrences = 0u;

    for (size_t start = 0u; (start + needle_len) <= length; start++)
    {
        if (memcmp(&corpus[start], needle, needle_len) != 0)
        {
            continue;
        }
        occurrences++;

        for (unsigned index = 0u; index < count; index++)
        {
            if (corpus[start + offsets[index]] != needle[offsets[index]])
            {
                refused++;
                break;
            }
        }
    }
    *found = occurrences;
    return refused;
}

static void report_invariant(const char *name, const uint8_t *corpus, size_t corpus_len, size_t needle_len,
                             AnchorPolicy policy, uint32_t stamp)
{
    if ((needle_len == 0u) || (needle_len > corpus_len))
    {
        return;
    }

    const size_t positions = (corpus_len - needle_len) + 1u;

    const size_t wanted = (needle_len > 128u) ? 8u : NEEDLE_SAMPLES;
    const size_t step = (positions > wanted) ? (positions / wanted) : 1u;

    for (unsigned count = 1u; count <= CASCADE_MAX; count++)
    {
        uint32_t checked = 0u;
        uint32_t refused = 0u;
        unsigned samples = 0u;

        for (size_t at = 0u; at < positions; at += step)
        {
            const uint8_t *const needle = &corpus[at];
            size_t offsets[CASCADE_MAX];
            const unsigned taken = pick_anchors(needle, needle_len, policy, offsets, count);

            if (taken < count)
            {
                continue;
            }

            uint32_t found = 0u;

            refused += refused_occurrences(corpus, corpus_len, needle, needle_len, offsets, count, &found);
            checked += found;
            samples++;
        }

        printf("ancorae_invariant,%08x,%s,%s,%u,%u,%u,%u,%u,%u,%s\n", stamp, name, policy_name(policy),
               (unsigned)needle_len, count, (unsigned)corpus_len, samples, checked, refused,
               (checked == 0u) ? "none" : ((refused == 0u) ? "hold" : "BROKEN"));
    }
}

static void report(const char *name, const uint8_t *corpus, size_t corpus_len, size_t needle_len, size_t anchor_stride,
                   AnchorPolicy policy, uint32_t stamp)
{
    if (needle_len >= (corpus_len / 4u))
    {
        return;
    }

    uint32_t counts[256];
    histogram(corpus, corpus_len, counts);

    double one_total = 0.0;
    double two_total = 0.0;
    double two_squares = 0.0;
    double predicted_total = 0.0;
    unsigned samples = 0u;

    const size_t step = (corpus_len - needle_len) / NEEDLE_SAMPLES;

    for (size_t sample = 0u; sample < NEEDLE_SAMPLES; sample++)
    {
        const size_t at = sample * step;
        const uint8_t *const needle = &corpus[at];

        const size_t first_at = cheapest_offset(needle, needle_len, needle_len, policy);

        size_t second_at;

        if (anchor_stride == 0u)
        {
            second_at = cheapest_offset(needle, needle_len, first_at, policy);
        }
        else
        {
            second_at = first_at + anchor_stride;
            if (second_at >= needle_len)
            {
                continue;
            }
        }

        if ((first_at == needle_len) || (second_at == needle_len))
        {
            continue;
        }

        const uint32_t one = candidates(corpus, corpus_len, needle[first_at], first_at, 0u, (size_t)-1, needle_len);
        const uint32_t two = candidates(corpus, corpus_len, needle[first_at], first_at, needle[second_at], second_at,
                                        needle_len);

        const double positions = (double)(corpus_len - needle_len + 1u);
        const double second_rate = (double)counts[needle[second_at]] / (double)corpus_len;

        const double two_excess = (double)two - 1.0;

        one_total += (double)one;
        two_total += two_excess;
        two_squares += two_excess * two_excess;
        predicted_total += ((double)one - 1.0) * second_rate;
        (void)positions;
        samples++;
    }

    if (samples == 0u)
    {
        return;
    }

    const double count = (double)samples;
    const double one_mean = (one_total / count) - 1.0;
    const double two_mean = two_total / count;
    const double predicted_mean = predicted_total / count;
    const double skip = (one_mean > 0.0) ? ((double)corpus_len / one_mean) : 0.0;
    const double independence = (predicted_mean > 0.0) ? (two_mean / predicted_mean) : 0.0;

    const double variance = (count > 1.0) ? ((two_squares - (count * two_mean * two_mean)) / (count - 1.0)) : 0.0;
    const double stderr_two = (variance > 0.0) ? (sqrt(variance) / sqrt(count)) : 0.0;

    const double zscore = (stderr_two > 0.0) ? ((two_mean - predicted_mean) / stderr_two) : 0.0;

    printf("ancorae_sift,%08x,%s,%s,%u,%u,%u,%u,%.2f,%.2f,%.2f,%.1f,%.2f,%.3f,%.1f\n", stamp, name,
           policy_name(policy), (unsigned)needle_len, (unsigned)anchor_stride, (unsigned)corpus_len, samples,
           one_mean, two_mean, predicted_mean, skip, independence, stderr_two, zscore);
}

static void report_domain(const char *name, const uint8_t *corpus, size_t corpus_len, size_t needle_len,
                          uint32_t stamp)
{
    uint32_t counts[256];
    unsigned distinct = 0u;
    double shannon = 0.0;
    double collision = 0.0;

    histogram(corpus, corpus_len, counts);

    for (unsigned byte = 0u; byte < 256u; byte++)
    {
        if (counts[byte] == 0u)
        {
            continue;
        }

        const double share = (double)counts[byte] / (double)corpus_len;

        distinct++;
        shannon -= share * log2(share);
        collision += share * share;
    }

    const double positions = (double)((corpus_len - needle_len) + 1u);

    double shares[256];
    unsigned carried = 0u;

    for (unsigned byte = 0u; byte < 256u; byte++)
    {
        if (counts[byte] != 0u)
        {
            shares[carried] = (double)counts[byte] / (double)corpus_len;
            carried++;
        }
    }
    for (unsigned outer = 1u; outer < carried; outer++)
    {
        const double held = shares[outer];
        unsigned inner = outer;

        while ((inner > 0u) && (shares[inner - 1u] > held))
        {
            shares[inner] = shares[inner - 1u];
            inner--;
        }
        shares[inner] = held;
    }

    double expected_min = 0.0;
    double previous = 0.0;
    double heavier = 1.0;

    for (unsigned index = 0u; index < carried; index++)
    {
        expected_min += (shares[index] - previous) * pow(heavier, (double)needle_len);
        heavier -= shares[index];
        previous = shares[index];
    }

    printf("ancorae_domain,%08x,%s,%u,%u,%u,%.4f,%.4f,%.6f,%.2f,%.3f,%.8f,%.3f\n", stamp, name,
           (unsigned)corpus_len, (unsigned)needle_len, distinct, shannon, -log2(collision), collision,
           1.0 / collision, positions * collision, expected_min,
           (expected_min > 0.0) ? (collision / expected_min) : 0.0);
}

static void report_refutation(const char *name, const uint8_t *corpus, size_t corpus_len, size_t needle_len,
                              AnchorPolicy policy, uint32_t stamp)
{
    if (needle_len >= (corpus_len / 4u))
    {
        return;
    }

    uint32_t counts[256];
    histogram(corpus, corpus_len, counts);

    double collision = 0.0;

    for (unsigned byte = 0u; byte < 256u; byte++)
    {
        const double share = (double)counts[byte] / (double)corpus_len;

        collision += share * share;
    }

    const size_t step = (corpus_len - needle_len) / NEEDLE_SAMPLES;
    double refuted = 0.0;
    double observations = 0.0;
    unsigned samples = 0u;

    for (size_t sample = 0u; sample < NEEDLE_SAMPLES; sample++)
    {
        const uint8_t *const needle = &corpus[sample * step];
        const size_t anchor = cheapest_offset(needle, needle_len, needle_len, policy);

        if (anchor == needle_len)
        {
            continue;
        }

        uint32_t inside[256];

        for (unsigned byte = 0u; byte < 256u; byte++)
        {
            inside[byte] = 0u;
        }
        for (size_t index = 0u; index < needle_len; index++)
        {
            inside[needle[index]]++;
        }

        for (size_t start = 0u; (start + needle_len) <= corpus_len; start++)
        {
            const uint8_t seen = corpus[start + anchor];

            refuted += (double)needle_len - (double)inside[seen];
            observations += 1.0;
        }
        samples++;
    }

    if (samples == 0u)
    {
        return;
    }

    const double mean = refuted / observations;
    const double predicted = (double)needle_len * (1.0 - collision);

    printf("ancorae_refutation,%08x,%s,%s,%u,%u,%u,%.4f,%.4f,%.3f\n", stamp, name, policy_name(policy),
           (unsigned)needle_len, (unsigned)corpus_len, samples, mean, predicted,
           (predicted > 0.0) ? (mean / predicted) : 0.0);
}

#define WIDEST_SYMBOL 16u

static uint32_t s_width_counts[1u << WIDEST_SYMBOL];

static void report_widths(const char *name, const uint8_t *corpus, size_t corpus_len, uint32_t stamp)
{
    const size_t total_bits = corpus_len * 8u;

    for (unsigned width = 1u; width <= WIDEST_SYMBOL; width++)
    {
        if ((width != 1u) && (width != 2u) && (width != 3u) && (width != 4u) && (width != 6u) &&
            (width != 8u) && (width != 12u) && (width != 16u))
        {
            continue;
        }

        const uint32_t values = 1u << width;

        for (uint32_t value = 0u; value < values; value++)
        {
            s_width_counts[value] = 0u;
        }

        size_t drawn = 0u;

        for (size_t bit = 0u; (bit + width) <= total_bits; bit++)
        {
            uint32_t symbol = 0u;

            for (unsigned step = 0u; step < width; step++)
            {
                const size_t at = bit + step;
                const unsigned held = (corpus[at / 8u] >> (7u - (at % 8u))) & 1u;

                symbol = (symbol << 1) | held;
            }
            s_width_counts[symbol]++;
            drawn++;
        }

        double collision = 0.0;
        unsigned distinct = 0u;

        for (uint32_t value = 0u; value < values; value++)
        {
            if (s_width_counts[value] == 0u)
            {
                continue;
            }

            const double share = (double)s_width_counts[value] / (double)drawn;

            distinct++;
            collision += share * share;
        }

        const double renyi = -log2(collision);

        printf("ancorae_width,%08x,%s,%u,%u,%u,%u,%.4f,%.4f\n", stamp, name, (unsigned)corpus_len, width,
               values, distinct, renyi, renyi / (double)width);
    }
}

int main(void)
{
    const size_t english_len = fill_from_text(s_english_corpus, s_english, CORPUS_BYTES);
    const size_t structured_len = fill_from_text(s_structured_corpus, s_structured, CORPUS_BYTES);
    const size_t periodic_len = fill_periodic(s_periodic_corpus, CORPUS_BYTES);

    fill_uniform(s_uniform_corpus, CORPUS_BYTES);
    fill_random_costs();

    for (size_t index = 0u; index < CORPUS_BYTES; index++)
    {
        s_flat_corpus[index] = (uint8_t)'A';
    }

    const uint32_t stamp = table_fingerprint();

    static const AnchorPolicy policies[] = {ANCHOR_BY_TABLE, ANCHOR_BY_RANDOM, ANCHOR_BY_MAXIMUM_ENTROPY};

    printf("bench,table,corpus,policy,needle_len,stride,corpus_bytes,samples,one_anchor,two_anchor,predicted,"
           "skip,independence,stderr,z\n");
    printf("bench,table,corpus,policy,needle_len,anchors,corpus_bytes,samples,candidates,predicted,ratio,z\n");
    printf("bench,table,corpus,policy,needle_len,anchors,corpus_bytes,samples,occurrences,refused,verdict\n");
    printf("bench,table,corpus,corpus_bytes,needle_len,distinct,shannon,renyi2,collision,effective_alphabet,"
           "predicted_maxent,oracle_rate,ceiling\n");

    report_domain("english", s_english_corpus, english_len, 16u, stamp);
    report_domain("structured", s_structured_corpus, structured_len, 16u, stamp);
    report_domain("periodic16", s_periodic_corpus, periodic_len, 16u, stamp);
    report_domain("uniform", s_uniform_corpus, CORPUS_BYTES, 16u, stamp);
    report_domain("flat", s_flat_corpus, CORPUS_BYTES, 16u, stamp);

    printf("bench,table,corpus,corpus_bytes,symbol_bits,alphabet,distinct,renyi2,renyi2_per_bit\n");

    report_widths("english", s_english_corpus, english_len, stamp);
    report_widths("structured", s_structured_corpus, structured_len, stamp);
    report_widths("periodic16", s_periodic_corpus, periodic_len, stamp);
    report_widths("uniform", s_uniform_corpus, CORPUS_BYTES, stamp);
    report_widths("flat", s_flat_corpus, CORPUS_BYTES, stamp);

    static const size_t lengths[] = {4u, 8u, 16u, 32u, 64u, 128u, 256u};

    static const size_t strides[] = {0u, 1u, 2u, 3u, 4u, 5u, 7u, 8u, 11u, 13u, 16u, 17u};

    static const size_t limits[] = {1u, 2u, 3u, 4u, 16u, 64u, 256u, 1024u, CORPUS_BYTES};

    for (size_t which_policy = 0u; which_policy < (sizeof policies / sizeof policies[0]); which_policy++)
    {
        const AnchorPolicy policy = policies[which_policy];

        for (size_t index = 0u; index < (sizeof lengths / sizeof lengths[0]); index++)
        {
            for (size_t which = 0u; which < (sizeof strides / sizeof strides[0]); which++)
            {
                report("english", s_english_corpus, english_len, lengths[index], strides[which], policy, stamp);
                report("structured", s_structured_corpus, structured_len, lengths[index], strides[which], policy,
                       stamp);
                report("periodic16", s_periodic_corpus, periodic_len, lengths[index], strides[which], policy, stamp);
                report("uniform", s_uniform_corpus, CORPUS_BYTES, lengths[index], strides[which], policy, stamp);
            }

            report_cascade("english", s_english_corpus, english_len, lengths[index], policy, stamp);
            report_cascade("structured", s_structured_corpus, structured_len, lengths[index], policy, stamp);
            report_cascade("periodic16", s_periodic_corpus, periodic_len, lengths[index], policy, stamp);
            report_cascade("uniform", s_uniform_corpus, CORPUS_BYTES, lengths[index], policy, stamp);

            report_cascade("flat", s_flat_corpus, CORPUS_BYTES, lengths[index], policy, stamp);

            report_refutation("english", s_english_corpus, english_len, lengths[index], policy, stamp);
            report_refutation("structured", s_structured_corpus, structured_len, lengths[index], policy, stamp);
            report_refutation("periodic16", s_periodic_corpus, periodic_len, lengths[index], policy, stamp);
            report_refutation("uniform", s_uniform_corpus, CORPUS_BYTES, lengths[index], policy, stamp);
            report_refutation("flat", s_flat_corpus, CORPUS_BYTES, lengths[index], policy, stamp);
        }

        for (size_t index = 0u; index < (sizeof limits / sizeof limits[0]); index++)
        {
            report_invariant("english", s_english_corpus, english_len, limits[index], policy, stamp);
            report_invariant("structured", s_structured_corpus, structured_len, limits[index], policy, stamp);
            report_invariant("periodic16", s_periodic_corpus, periodic_len, limits[index], policy, stamp);
            report_invariant("uniform", s_uniform_corpus, CORPUS_BYTES, limits[index], policy, stamp);
            report_invariant("flat", s_flat_corpus, CORPUS_BYTES, limits[index], policy, stamp);
        }
    }
    return 0;
}
