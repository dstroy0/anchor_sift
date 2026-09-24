// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "impensa_ancorae_acus/impensa_ancorae_acus.h"

#include "mmgr_sha256.h"

#include <math.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define AB_CORPUS_BYTES 4096u

#define AB_SAMPLES 64u

#define AB_MAX_NEEDLE 256u

#define AB_FILE_BYTES (1u << 20)

#define AB_FILE_UNITS (1u << 18)

#define AB_TOKEN_BUDGET 25000u

typedef struct
{
    uint64_t reads;
    uint32_t found;
} AbResult;

static uint8_t s_ab_english[AB_CORPUS_BYTES];
static uint8_t s_ab_structured[AB_CORPUS_BYTES];
static uint8_t s_ab_periodic[AB_CORPUS_BYTES];
static uint8_t s_ab_uniform[AB_CORPUS_BYTES];

static uint8_t s_ab_mixed[AB_CORPUS_BYTES];

static const char s_ab_prose[] =
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
    "made camp where they stood and did not risk the descent in darkness. the fire took a long "
    "while to catch because everything was wet, and when it did catch it smoked badly and gave "
    "very little heat, but it was something to sit beside and they were both glad of it. in the "
    "morning the sky had cleared completely and the grass was heavy with water that soaked their "
    "boots within the first few steps. neither of them mentioned the conversation of the previous "
    "evening, though both remembered it, and they walked down toward the village in a silence "
    "that was comfortable and not awkward. the bakery was already open when they arrived and "
    "the smell of it reached them from a considerable distance up the road, which improved their "
    "mood more than anything either of them could have said. ";

static const char s_ab_source[] =
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
    "}\n";

static size_t ab_fill_text(uint8_t *into, const char *text, size_t length)
{
    const size_t available = strlen(text);
    const size_t usable = (available < length) ? available : length;

    for (size_t index = 0u; index < usable; index++)
    {
        into[index] = (uint8_t)text[index];
    }
    return usable;
}

static size_t ab_fill_periodic(uint8_t *into, size_t length)
{
    static const char digits[] = "0123456789abcdef";
    const size_t records = length / 16u;

    for (size_t record = 0u; record < records; record++)
    {
        uint8_t *const at = &into[record * 16u];
        const size_t counter = record * 2654435761u;

        at[0] = (uint8_t)digits[(counter >> 12) & 0xFu];
        at[1] = (uint8_t)digits[(counter >> 8) & 0xFu];
        at[2] = (uint8_t)digits[(counter >> 4) & 0xFu];
        at[3] = (uint8_t)digits[counter & 0xFu];
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
    return records * 16u;
}

static void ab_fill_uniform(uint8_t *into, size_t length)
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

static AbResult ab_naive(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle, size_t needle_len)
{
    AbResult result = {0u, 0u};

    for (size_t start = 0u; (start + needle_len) <= corpus_len; start++)
    {
        size_t index = 0u;

        while (index < needle_len)
        {
            result.reads++;
            if (corpus[start + index] != needle[index])
            {
                break;
            }
            index++;
        }
        if (index == needle_len)
        {
            result.found++;
        }
    }
    return result;
}

static AbResult ab_kmp(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle, size_t needle_len)
{
    static size_t border[AB_MAX_NEEDLE];
    AbResult result = {0u, 0u};
    size_t length = 0u;

    border[0] = 0u;
    for (size_t index = 1u; index < needle_len; index++)
    {
        while ((length > 0u) && (needle[index] != needle[length]))
        {
            length = border[length - 1u];
        }
        if (needle[index] == needle[length])
        {
            length++;
        }
        border[index] = length;
    }

    size_t state = 0u;

    for (size_t at = 0u; at < corpus_len; at++)
    {
        const uint8_t seen = corpus[at];

        result.reads++;
        while ((state > 0u) && (seen != needle[state]))
        {
            state = border[state - 1u];
        }
        if (seen == needle[state])
        {
            state++;
        }
        if (state == needle_len)
        {
            result.found++;
            state = border[state - 1u];
        }
    }
    return result;
}

static AbResult ab_anchored(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle, size_t needle_len,
                            size_t anchor)
{
    size_t advance[256];
    AbResult result = {0u, 0u};

    for (unsigned byte = 0u; byte < 256u; byte++)
    {
        advance[byte] = anchor + 1u;
    }
    for (size_t index = 0u; index < anchor; index++)
    {
        advance[needle[index]] = anchor - index;
    }

    size_t start = 0u;

    while ((start + needle_len) <= corpus_len)
    {
        const uint8_t seen = corpus[start + anchor];

        result.reads++;
        if (seen == needle[anchor])
        {
            size_t index = 0u;

            while (index < needle_len)
            {
                if (index != anchor)
                {
                    result.reads++;
                    if (corpus[start + index] != needle[index])
                    {
                        break;
                    }
                }
                index++;
            }
            if (index == needle_len)
            {
                result.found++;
            }
            start++;
        }
        else
        {
            start += advance[seen];
        }
    }
    return result;
}

static AbResult ab_horspool_rare(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle, size_t needle_len,
                                 size_t rare)
{
    size_t advance[256];
    AbResult result = {0u, 0u};
    const size_t anchor = needle_len - 1u;

    for (unsigned byte = 0u; byte < 256u; byte++)
    {
        advance[byte] = anchor + 1u;
    }
    for (size_t index = 0u; index < anchor; index++)
    {
        advance[needle[index]] = anchor - index;
    }

    size_t start = 0u;

    while ((start + needle_len) <= corpus_len)
    {
        const uint8_t seen = corpus[start + anchor];

        result.reads++;
        if (seen != needle[anchor])
        {
            start += advance[seen];
            continue;
        }

        if (rare != anchor)
        {
            result.reads++;
            if (corpus[start + rare] != needle[rare])
            {
                start++;
                continue;
            }
        }

        size_t index = 0u;

        while (index < needle_len)
        {
            if ((index != anchor) && (index != rare))
            {
                result.reads++;
                if (corpus[start + index] != needle[index])
                {
                    break;
                }
            }
            index++;
        }
        if (index == needle_len)
        {
            result.found++;
        }
        start++;
    }
    return result;
}

static size_t ab_best_anchor(const uint8_t *needle, size_t length, const double *frequency)
{
    size_t best = length - 1u;
    double best_value = -1.0;

    for (size_t anchor = 0u; anchor < length; anchor++)
    {
        size_t advance[256];

        for (unsigned byte = 0u; byte < 256u; byte++)
        {
            advance[byte] = anchor + 1u;
        }
        for (size_t index = 0u; index < anchor; index++)
        {
            advance[needle[index]] = anchor - index;
        }
        advance[needle[anchor]] = 1u;

        double value = 0.0;

        for (unsigned byte = 0u; byte < 256u; byte++)
        {
            value += frequency[byte] * (double)advance[byte];
        }
        if (value > best_value)
        {
            best_value = value;
            best = anchor;
        }
    }
    return best;
}

static AbResult ab_interrogative(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle, size_t needle_len,
                                 uint32_t *carried)
{
    uint32_t local_count[256];
    uint32_t *const seen_count = (carried != NULL) ? carried : local_count;
    double estimate[256];
    size_t advance[256];
    AbResult result = {0u, 0u};

    if (carried == NULL)
    {
        for (unsigned byte = 0u; byte < 256u; byte++)
        {
            local_count[byte] = 1u;
        }
    }

    double total = 0.0;

    for (unsigned byte = 0u; byte < 256u; byte++)
    {
        total += (double)seen_count[byte];
    }
    size_t anchor = needle_len - 1u;
    size_t since_review = 0u;
    size_t start = 0u;

    for (unsigned byte = 0u; byte < 256u; byte++)
    {
        advance[byte] = anchor + 1u;
    }
    for (size_t index = 0u; index < anchor; index++)
    {
        advance[needle[index]] = anchor - index;
    }
    advance[needle[anchor]] = 1u;

    while ((start + needle_len) <= corpus_len)
    {
        const uint8_t answer = corpus[start + anchor];

        result.reads++;
        seen_count[answer]++;
        total += 1.0;
        since_review++;

        if (answer == needle[anchor])
        {
            size_t index = 0u;

            while (index < needle_len)
            {
                if (index != anchor)
                {
                    result.reads++;
                    seen_count[corpus[start + index]]++;
                    total += 1.0;
                    if (corpus[start + index] != needle[index])
                    {
                        break;
                    }
                }
                index++;
            }
            if (index == needle_len)
            {
                result.found++;
            }
            start++;
        }
        else
        {
            start += advance[answer];
        }

        if (since_review < needle_len)
        {
            continue;
        }
        since_review = 0u;

        for (unsigned byte = 0u; byte < 256u; byte++)
        {
            estimate[byte] = (double)seen_count[byte] / total;
        }

        const size_t chosen = ab_best_anchor(needle, needle_len, estimate);

        if (chosen != anchor)
        {
            anchor = chosen;
        }
        for (unsigned byte = 0u; byte < 256u; byte++)
        {
            advance[byte] = anchor + 1u;
        }
        for (size_t index = 0u; index < anchor; index++)
        {
            advance[needle[index]] = anchor - index;
        }
        advance[needle[anchor]] = 1u;
    }
    return result;
}

static AbResult ab_distance_only(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle, size_t needle_len,
                                 double *carried, unsigned steer, unsigned pull_to_center, double gain_now,
                                 double gain_history, double gain_trend)
{
    double local_value[AB_MAX_NEEDLE];
    double *const value = (carried != NULL) ? carried : local_value;
    size_t advance[256];
    AbResult result = {0u, 0u};

    double recent = 0.0;
    double settled = 0.0;
    size_t since_reset = 0u;

    double background = (double)needle_len / 2.0;

    double history[AB_MAX_NEEDLE];
    double last_error[AB_MAX_NEEDLE];

    for (size_t offset = 0u; offset < needle_len; offset++)
    {
        history[offset] = 0.0;
        last_error[offset] = 0.0;
    }

    if (carried == NULL)
    {
        for (size_t offset = 0u; offset < needle_len; offset++)
        {
            value[offset] = (double)(offset + 1u);
        }
    }

    size_t anchor = needle_len - 1u;
    size_t since_review = 0u;
    size_t start = 0u;

    for (unsigned byte = 0u; byte < 256u; byte++)
    {
        advance[byte] = anchor + 1u;
    }
    for (size_t index = 0u; index < anchor; index++)
    {
        advance[needle[index]] = anchor - index;
    }
    advance[needle[anchor]] = 1u;

    while ((start + needle_len) <= corpus_len)
    {
        const uint8_t answer = corpus[start + anchor];
        size_t traveled;

        result.reads++;
        since_review++;

        if (answer == needle[anchor])
        {
            size_t index = 0u;

            while (index < needle_len)
            {
                if (index != anchor)
                {
                    result.reads++;
                    if (corpus[start + index] != needle[index])
                    {
                        break;
                    }
                }
                index++;
            }
            if (index == needle_len)
            {
                result.found++;
            }
            traveled = 1u;
        }
        else
        {
            traveled = advance[answer];
        }
        start += traveled;

        size_t previous = needle_len;

        for (size_t offset = 0u; offset < needle_len; offset++)
        {
            const double would_travel =
                (needle[offset] == answer) ? 1.0
                                           : ((previous == needle_len) ? (double)(offset + 1u)
                                                                       : (double)(offset - previous));

            if (gain_trend < 0.0)
            {
                const double excess = would_travel - background;
                const double deadband = 0.25 * background;

                if ((excess > deadband) || (excess < -deadband))
                {
                    value[offset] += gain_now * (would_travel - value[offset]);
                }
                else
                {
                    value[offset] += gain_history * ((double)(offset + 1u) - value[offset]);
                }
                if (needle[offset] == answer)
                {
                    previous = offset;
                }
                continue;
            }

            const double error = would_travel - value[offset];
            const double trend = error - last_error[offset];

            history[offset] += error;
            if (history[offset] > 64.0)
            {
                history[offset] = 64.0;
            }
            if (history[offset] < -64.0)
            {
                history[offset] = -64.0;
            }

            value[offset] += (gain_now * error) + (gain_history * history[offset]) + (gain_trend * trend);
            last_error[offset] = error;

            if (needle[offset] == answer)
            {
                previous = offset;
            }
        }

        recent += 0.30 * ((double)traveled - recent);
        settled += 0.02 * ((double)traveled - settled);
        background += 0.02 * ((double)traveled - background);
        since_reset++;

        if ((steer != 0u) && (since_reset > (4u * needle_len)) && (recent < (0.6 * settled)))
        {
            for (size_t offset = 0u; offset < needle_len; offset++)
            {
                value[offset] = (double)(offset + 1u);
            }
            recent = 0.0;
            settled = 0.0;
            since_reset = 0u;
            since_review = 8u;
        }

        if (since_review < 8u)
        {
            continue;
        }
        since_review = 0u;

        size_t best = anchor;

        if (pull_to_center != 0u)
        {
            double mass = 0.0;
            double moment = 0.0;

            for (size_t offset = 0u; offset < needle_len; offset++)
            {
                mass += value[offset];
                moment += value[offset] * (double)offset;
            }
            best = (mass > 0.0) ? (size_t)((moment / mass) + 0.5) : anchor;
            if (best >= needle_len)
            {
                best = needle_len - 1u;
            }
        }
        else
        {
            for (size_t offset = 0u; offset < needle_len; offset++)
            {
                if (value[offset] > value[best])
                {
                    best = offset;
                }
            }
        }
        if (best == anchor)
        {
            continue;
        }
        anchor = best;

        for (unsigned byte = 0u; byte < 256u; byte++)
        {
            advance[byte] = anchor + 1u;
        }
        for (size_t index = 0u; index < anchor; index++)
        {
            advance[needle[index]] = anchor - index;
        }
        advance[needle[anchor]] = 1u;
    }
    return result;
}

static AbResult ab_free_order(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle, size_t needle_len,
                              size_t stride, size_t *depth, unsigned confirm, uint64_t *mirror)
{
    static uint8_t alive[AB_CORPUS_BYTES];
    AbResult result = {0u, 0u};

    if ((needle_len == 0u) || (corpus_len < needle_len))
    {
        *depth = 0u;
        return result;
    }

    const size_t alignments = (corpus_len - needle_len) + 1u;

    for (size_t start = 0u; start < alignments; start++)
    {
        alive[start] = 1u;
    }

    for (size_t at = 0u; at < corpus_len; at += stride)
    {
        const uint8_t answer = corpus[at];
        const size_t lowest = (at >= (needle_len - 1u)) ? ((at - needle_len) + 1u) : 0u;
        const size_t highest = (at < alignments) ? at : (alignments - 1u);

        result.reads++;

        for (size_t start = lowest; start <= highest; start++)
        {
            if ((alive[start] != 0u) && (needle[at - start] != answer))
            {
                alive[start] = 0u;
            }
        }
    }

    if (mirror != NULL)
    {
        for (size_t start = 0u; start < alignments; start++)
        {
            if (alive[start] == 0u)
            {
                continue;
            }
            for (size_t past = 0u; past < corpus_len; past += stride)
            {
                if ((past < start) || ((past - start) >= needle_len))
                {
                    continue;
                }
                if (needle[past - start] != corpus[past])
                {
                    (*mirror)++;
                }
            }
        }
    }

    *depth = 0u;

    for (size_t start = 0u; start < alignments; start++)
    {
        if (alive[start] == 0u)
        {
            continue;
        }
        (*depth)++;

        if (confirm == 0u)
        {
            result.found++;
            continue;
        }

        size_t index = 0u;

        while (index < needle_len)
        {
            if ((((start + index) % stride) != 0u))
            {
                result.reads++;
                if (corpus[start + index] != needle[index])
                {
                    break;
                }
            }
            else if (corpus[start + index] != needle[index])
            {
                break;
            }
            index++;
        }
        if (index == needle_len)
        {
            result.found++;
        }
    }

    return result;
}

static AbResult ab_adaptive(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle, size_t needle_len,
                            size_t *probes, uint64_t *mirror)
{
    static uint8_t alive[AB_CORPUS_BYTES];
    static uint8_t probed[AB_CORPUS_BYTES];
    static uint32_t before[AB_CORPUS_BYTES + 1u];
    AbResult result = {0u, 0u};

    *probes = 0u;
    if ((needle_len == 0u) || (corpus_len < needle_len))
    {
        return result;
    }

    const size_t alignments = (corpus_len - needle_len) + 1u;
    size_t living = alignments;

    for (size_t start = 0u; start < alignments; start++)
    {
        alive[start] = 1u;
    }
    for (size_t at = 0u; at < corpus_len; at++)
    {
        probed[at] = 0u;
    }

    unsigned stalled = 0u;

    while ((living > 1u) && (stalled < 2u))
    {
        before[0] = 0u;
        for (size_t start = 0u; start < alignments; start++)
        {
            before[start + 1u] = before[start] + (uint32_t)alive[start];
        }

        size_t chosen = corpus_len;
        uint32_t best = 0u;

        for (size_t at = 0u; at < corpus_len; at++)
        {
            if (probed[at] != 0u)
            {
                continue;
            }

            const size_t lowest = (at >= (needle_len - 1u)) ? ((at - needle_len) + 1u) : 0u;
            const size_t highest = (at < alignments) ? at : (alignments - 1u);

            if (lowest > highest)
            {
                continue;
            }

            const uint32_t covered = before[highest + 1u] - before[lowest];

            if (covered > best)
            {
                best = covered;
                chosen = at;
            }
        }

        if ((chosen == corpus_len) || (best == 0u))
        {
            break;
        }

        const uint8_t answer = corpus[chosen];
        const size_t lowest = (chosen >= (needle_len - 1u)) ? ((chosen - needle_len) + 1u) : 0u;
        const size_t highest = (chosen < alignments) ? chosen : (alignments - 1u);
        size_t killed = 0u;

        probed[chosen] = 1u;
        result.reads++;
        (*probes)++;

        for (size_t start = lowest; start <= highest; start++)
        {
            if ((alive[start] != 0u) && (needle[chosen - start] != answer))
            {
                alive[start] = 0u;
                killed++;
            }
        }
        living -= killed;
        stalled = (killed == 0u) ? (stalled + 1u) : 0u;
    }

    for (size_t start = 0u; start < alignments; start++)
    {
        if (alive[start] == 0u)
        {
            continue;
        }

        if (mirror != NULL)
        {
            for (size_t at = 0u; at < corpus_len; at++)
            {
                if ((probed[at] == 0u) || (at < start) || ((at - start) >= needle_len))
                {
                    continue;
                }
                if (needle[at - start] != corpus[at])
                {
                    (*mirror)++;
                }
            }
        }

        size_t index = 0u;

        while (index < needle_len)
        {
            if (probed[start + index] == 0u)
            {
                result.reads++;
                if (corpus[start + index] != needle[index])
                {
                    break;
                }
            }
            else if (corpus[start + index] != needle[index])
            {
                break;
            }
            index++;
        }
        if (index == needle_len)
        {
            result.found++;
        }
    }
    return result;
}

#define AB_DISCOVER_READS 512u

static void ab_draw_noise(uint8_t *into, size_t length, uint64_t salt)
{
    uint8_t seed[16];
    uint8_t digest[MMGR_SHA256_BYTES];
    size_t written = 0u;
    uint64_t block = 0u;

    while (written < length)
    {
        for (unsigned index = 0u; index < 8u; index++)
        {
            seed[index] = (uint8_t)((salt >> (56u - (index * 8u))) & 0xFFu);
            seed[8u + index] = (uint8_t)((block >> (56u - (index * 8u))) & 0xFFu);
        }
        mmgr_sha256(seed, sizeof seed, digest);

        for (unsigned index = 0u; (index < MMGR_SHA256_BYTES) && (written < length); index++)
        {
            into[written] = digest[index];
            written++;
        }
        block++;
    }
}

static double ab_shift_survey(const uint8_t *corpus, size_t corpus_len, unsigned *found, double *peak,
                              size_t *peak_shift)
{
    static size_t spots[AB_DISCOVER_READS];
    static uint8_t seen[AB_DISCOVER_READS];
    static uint32_t tests[AB_CORPUS_BYTES];
    static uint32_t agrees[AB_CORPUS_BYTES];
    static uint8_t noise[AB_DISCOVER_READS * 2u];

    ab_draw_noise(noise, sizeof noise, 0xD15C0FEEuLL);

    for (unsigned index = 0u; index < AB_DISCOVER_READS; index++)
    {
        const uint32_t drawn = ((uint32_t)noise[index * 2u] << 8) | (uint32_t)noise[(index * 2u) + 1u];

        spots[index] = (size_t)(drawn % (uint32_t)corpus_len);
        seen[index] = corpus[spots[index]];
    }

    for (size_t shift = 0u; shift < corpus_len; shift++)
    {
        tests[shift] = 0u;
        agrees[shift] = 0u;
    }

    double collision = 0.0;
    uint32_t counts[256];

    for (unsigned byte = 0u; byte < 256u; byte++)
    {
        counts[byte] = 0u;
    }
    for (size_t index = 0u; index < corpus_len; index++)
    {
        counts[corpus[index]]++;
    }
    for (unsigned byte = 0u; byte < 256u; byte++)
    {
        const double share = (double)counts[byte] / (double)corpus_len;

        collision += share * share;
    }

    for (unsigned left = 0u; left < AB_DISCOVER_READS; left++)
    {
        for (unsigned right = left + 1u; right < AB_DISCOVER_READS; right++)
        {
            const size_t apart = (spots[left] > spots[right]) ? (spots[left] - spots[right])
                                                              : (spots[right] - spots[left]);
            if (apart == 0u)
            {
                continue;
            }

            tests[apart]++;
            if (seen[left] == seen[right])
            {
                agrees[apart]++;
            }
        }
    }

    unsigned reported = 0u;
    double strongest = 0.0;
    size_t strongest_shift = 0u;

    for (size_t shift = 1u; shift < corpus_len; shift++)
    {
        if (tests[shift] < 8u)
        {
            continue;
        }

        const double rate = (double)agrees[shift] / (double)tests[shift];
        const double spread = sqrt((collision * (1.0 - collision)) / (double)tests[shift]);
        const double excess = (spread > 0.0) ? ((rate - collision) / spread) : 0.0;

        if (excess > 6.0)
        {
            reported++;
        }
        if (excess > strongest)
        {
            strongest = excess;
            strongest_shift = shift;
        }
    }

    *found = reported;
    *peak = strongest;
    *peak_shift = strongest_shift;
    return collision;
}

static void ab_discover(const char *name, const uint8_t *corpus, size_t corpus_len)
{
    static uint8_t shuffled[AB_CORPUS_BYTES];
    static uint8_t noise[AB_CORPUS_BYTES * 2u];

    unsigned real_found = 0u;
    unsigned null_found = 0u;
    double real_peak = 0.0;
    double null_peak = 0.0;
    size_t real_shift = 0u;
    size_t null_shift = 0u;

    const double collision = ab_shift_survey(corpus, corpus_len, &real_found, &real_peak, &real_shift);

    for (size_t index = 0u; index < corpus_len; index++)
    {
        shuffled[index] = corpus[index];
    }
    ab_draw_noise(noise, corpus_len * 2u, 0x5417FFuLL);

    for (size_t slot = corpus_len - 1u; slot > 0u; slot--)
    {
        const uint32_t drawn = ((uint32_t)noise[slot * 2u] << 8) | (uint32_t)noise[(slot * 2u) + 1u];
        const size_t pick = (size_t)(drawn % (uint32_t)(slot + 1u));
        const uint8_t held = shuffled[slot];

        shuffled[slot] = shuffled[pick];
        shuffled[pick] = held;
    }

    (void)ab_shift_survey(shuffled, corpus_len, &null_found, &null_peak, &null_shift);

    printf("ancorae_discover,%s,%u,%.6f,%u,%u,%u,%.1f,%.1f\n", name, (unsigned)corpus_len, collision,
           real_found, null_found, (unsigned)real_shift, real_peak, null_peak);
}

static double ab_spacing(const uint8_t *corpus, size_t length, unsigned *which, double *gap)
{
    size_t seen_at[256];
    uint32_t counted[256];
    double total[256];
    double squares[256];

    for (unsigned byte = 0u; byte < 256u; byte++)
    {
        seen_at[byte] = length;
        counted[byte] = 0u;
        total[byte] = 0.0;
        squares[byte] = 0.0;
    }

    for (size_t at = 0u; at < length; at++)
    {
        const uint8_t held = corpus[at];

        if (seen_at[held] != length)
        {
            const double apart = (double)(at - seen_at[held]);

            counted[held]++;
            total[held] += apart;
            squares[held] += apart * apart;
        }
        seen_at[held] = at;
    }

    double tightest = 1.0;

    *which = 0u;
    *gap = 0.0;

    for (unsigned byte = 0u; byte < 256u; byte++)
    {
        if (counted[byte] < 16u)
        {
            continue;
        }

        const double runs = (double)counted[byte];
        const double mean = total[byte] / runs;
        const double spread = (squares[byte] / runs) - (mean * mean);
        const double dispersion = (mean > 0.0) ? (spread / (mean * mean)) : 1.0;

        if (dispersion < 0.05)
        {
            continue;
        }

        if (mean > 64.0)
        {
            continue;
        }

        if (dispersion < tightest)
        {
            tightest = dispersion;
            *which = byte;
            *gap = mean;
        }
    }
    return tightest;
}

static void ab_language(const char *name, const uint8_t *corpus, size_t corpus_len)
{
    static uint8_t shuffled[AB_FILE_BYTES];
    static uint8_t noise[AB_FILE_BYTES * 2u];

    unsigned real_byte = 0u;
    unsigned null_byte = 0u;
    double real_gap = 0.0;
    double null_gap = 0.0;

    const double real_tight = ab_spacing(corpus, corpus_len, &real_byte, &real_gap);

    for (size_t index = 0u; index < corpus_len; index++)
    {
        shuffled[index] = corpus[index];
    }
    ab_draw_noise(noise, corpus_len * 2u, 0xB0DEEuLL);

    for (size_t slot = corpus_len - 1u; slot > 0u; slot--)
    {
        const uint32_t drawn = ((uint32_t)noise[slot * 2u] << 8) | (uint32_t)noise[(slot * 2u) + 1u];
        const size_t pick = (size_t)(drawn % (uint32_t)(slot + 1u));
        const uint8_t held = shuffled[slot];

        shuffled[slot] = shuffled[pick];
        shuffled[pick] = held;
    }

    const double null_tight = ab_spacing(shuffled, corpus_len, &null_byte, &null_gap);

    printf("ancorae_language,%s,%u,%u,%.2f,%.4f,%u,%.4f,%.2f\n", name, (unsigned)corpus_len, real_byte,
           real_gap, real_tight, null_byte, null_tight,
           (real_tight > 0.0) ? (null_tight / real_tight) : 0.0);
}

static void ab_boundary_filter(const char *name, const uint8_t *corpus, size_t corpus_len, size_t needle_len,
                               uint8_t marker)
{
    size_t marked = 0u;

    for (size_t at = 0u; at < corpus_len; at++)
    {
        if (corpus[at] == marker)
        {
            marked++;
        }
    }
    if (marked < 4u)
    {
        return;
    }

    const size_t alignments = (corpus_len - needle_len) + 1u;
    const size_t step = (alignments > AB_SAMPLES) ? (alignments / AB_SAMPLES) : 1u;

    double survivors = 0.0;
    double signature = 0.0;
    unsigned samples = 0u;

    for (size_t at = 0u; at < alignments; at += step)
    {
        size_t inside[64];
        unsigned held = 0u;

        for (size_t index = 0u; (index < needle_len) && (held < 64u); index++)
        {
            if (corpus[at + index] == marker)
            {
                inside[held] = index;
                held++;
            }
        }
        if (held < 2u)
        {
            continue;
        }

        size_t kept = 0u;

        for (size_t start = 0u; start < alignments; start++)
        {
            unsigned matched = 0u;

            while (matched < held)
            {
                if (corpus[start + inside[matched]] != marker)
                {
                    break;
                }
                matched++;
            }
            if (matched == held)
            {
                kept++;
            }
        }

        survivors += (double)kept;
        signature += (double)held;
        samples++;
    }

    if (samples == 0u)
    {
        return;
    }

    const double count = (double)samples;
    const double mean_marks = signature / count;
    const double mean_kept = survivors / count;

    printf("ancorae_boundary,%s,%u,%u,%u,%.2f,%.2f,%.1f,%.4f\n", name, (unsigned)needle_len,
           (unsigned)corpus_len, (unsigned)marked, mean_marks, mean_kept,
           (double)alignments / ((mean_kept > 0.0) ? mean_kept : 1.0),
           (double)marked / (double)corpus_len);
}

typedef struct
{
    uint64_t stamp;
    uint32_t seen;
    uint32_t span;
} AbUnit;

static int ab_by_frequency(const void *left, const void *right)
{
    const AbUnit *const one = (const AbUnit *)left;
    const AbUnit *const other = (const AbUnit *)right;

    if (one->seen != other->seen)
    {
        return (one->seen < other->seen) ? 1 : -1;
    }
    return 0;
}

static int ab_by_stamp(const void *left, const void *right)
{
    const AbUnit *const one = (const AbUnit *)left;
    const AbUnit *const other = (const AbUnit *)right;

    if (one->stamp != other->stamp)
    {
        return (one->stamp < other->stamp) ? -1 : 1;
    }
    return 0;
}

static void ab_universals(const char *name, const uint8_t *corpus, size_t corpus_len, uint8_t marker)
{
    static AbUnit units[AB_FILE_UNITS];
    size_t held = 0u;
    size_t at = 0u;
    size_t distinct_budgeted = 0u;

    while ((at < corpus_len) && (held < AB_FILE_UNITS))
    {
        while ((at < corpus_len) && (corpus[at] == marker))
        {
            at++;
        }

        const size_t opened = at;
        uint64_t stamp = 1469598103934665603uLL;

        while ((at < corpus_len) && (corpus[at] != marker))
        {
            stamp ^= (uint64_t)corpus[at];
            stamp *= 1099511628211uLL;
            at++;
        }
        if (at > opened)
        {
            units[held].stamp = stamp;
            units[held].seen = 1u;
            units[held].span = (uint32_t)(at - opened);
            held++;
        }
    }

    if (held < 32u)
    {
        return;
    }

    qsort(units, held, sizeof units[0], ab_by_stamp);

    size_t distinct = 0u;

    for (size_t index = 0u; index < held;)
    {
        size_t run = index + 1u;

        while ((run < held) && (units[run].stamp == units[index].stamp))
        {
            run++;
        }
        units[distinct].stamp = units[index].stamp;
        units[distinct].seen = (uint32_t)(run - index);
        units[distinct].span = units[index].span;
        distinct++;
        index = run;
    }

    qsort(units, distinct, sizeof units[0], ab_by_frequency);

    const size_t ranked = (distinct < 100u) ? distinct : 100u;
    double sum_x = 0.0;
    double sum_y = 0.0;
    double sum_xx = 0.0;
    double sum_xy = 0.0;

    for (size_t index = 0u; index < ranked; index++)
    {
        const double rank = log((double)(index + 1u));
        const double freq = log((double)units[index].seen);

        sum_x += rank;
        sum_y += freq;
        sum_xx += rank * rank;
        sum_xy += rank * freq;
    }

    const double ranks = (double)ranked;
    const double denominator = (ranks * sum_xx) - (sum_x * sum_x);
    const double slope = (denominator != 0.0) ? (((ranks * sum_xy) - (sum_x * sum_y)) / denominator) : 0.0;

    double mean_span = 0.0;
    double mean_freq = 0.0;

    for (size_t index = 0u; index < distinct; index++)
    {
        mean_span += (double)units[index].span;
        mean_freq += log((double)units[index].seen);
    }
    mean_span /= (double)distinct;
    mean_freq /= (double)distinct;

    double covariance = 0.0;
    double span_spread = 0.0;
    double freq_spread = 0.0;

    for (size_t index = 0u; index < distinct; index++)
    {
        const double span_off = (double)units[index].span - mean_span;
        const double freq_off = log((double)units[index].seen) - mean_freq;

        covariance += span_off * freq_off;
        span_spread += span_off * span_off;
        freq_spread += freq_off * freq_off;
    }

    const double spread = sqrt(span_spread * freq_spread);
    const double brevity = (spread > 0.0) ? (covariance / spread) : 0.0;

    double carried = 0.0;

    if (held >= AB_TOKEN_BUDGET)
    {
        static AbUnit budgeted[AB_TOKEN_BUDGET];
        size_t taken = 0u;
        size_t walk = 0u;

        at = 0u;
        while ((at < corpus_len) && (taken < AB_TOKEN_BUDGET))
        {
            while ((at < corpus_len) && (corpus[at] == marker))
            {
                at++;
            }

            const size_t opened = at;
            uint64_t stamp = 1469598103934665603uLL;

            while ((at < corpus_len) && (corpus[at] != marker))
            {
                stamp ^= (uint64_t)corpus[at];
                stamp *= 1099511628211uLL;
                at++;
            }
            if (at > opened)
            {
                budgeted[taken].stamp = stamp;
                budgeted[taken].seen = 1u;
                budgeted[taken].span = (uint32_t)(at - opened);
                taken++;
            }
        }

        qsort(budgeted, taken, sizeof budgeted[0], ab_by_stamp);

        while (walk < taken)
        {
            size_t run = walk + 1u;

            while ((run < taken) && (budgeted[run].stamp == budgeted[walk].stamp))
            {
                run++;
            }

            const double share = (double)(run - walk) / (double)taken;

            carried -= share * log2(share);
            budgeted[distinct_budgeted] = budgeted[walk];
            distinct_budgeted++;
            walk = run;
        }
    }

    printf("ancorae_universal,%s,%u,%u,%u,%.2f,%.3f,%.3f,%u,%.3f\n", name, (unsigned)corpus_len,
           (unsigned)held, (unsigned)distinct, mean_span, slope, brevity, (unsigned)distinct_budgeted,
           carried);
}

typedef struct
{
    uint64_t stamp;
    uint64_t next;
    uint32_t where;
    uint32_t span;
} AbLink;

static int ab_by_pair(const void *left, const void *right)
{
    const AbLink *const one = (const AbLink *)left;
    const AbLink *const other = (const AbLink *)right;

    if (one->stamp != other->stamp)
    {
        return (one->stamp < other->stamp) ? -1 : 1;
    }
    if (one->next != other->next)
    {
        return (one->next < other->next) ? -1 : 1;
    }
    return 0;
}

static void ab_variety(const char *name, const uint8_t *corpus, size_t corpus_len, uint8_t marker)
{
    static AbLink links[AB_TOKEN_BUDGET];
    size_t taken = 0u;
    size_t at = 0u;

    while ((at < corpus_len) && (taken < AB_TOKEN_BUDGET))
    {
        while ((at < corpus_len) && (corpus[at] == marker))
        {
            at++;
        }

        const size_t opened = at;
        uint64_t stamp = 1469598103934665603uLL;

        while ((at < corpus_len) && (corpus[at] != marker))
        {
            stamp ^= (uint64_t)corpus[at];
            stamp *= 1099511628211uLL;
            at++;
        }
        if (at > opened)
        {
            links[taken].stamp = stamp;
            links[taken].where = (uint32_t)opened;
            links[taken].span = (uint32_t)(at - opened);
            taken++;
        }
    }

    if (taken < 1024u)
    {
        return;
    }

    for (size_t index = 0u; (index + 1u) < taken; index++)
    {
        links[index].next = links[index + 1u].stamp;
    }
    links[taken - 1u].next = 0u;

    qsort(links, taken, sizeof links[0], ab_by_pair);

    printf("# %s\n", name);

    size_t index = 0u;
    AbLink best[12];
    double score[12];
    size_t counted[12];
    size_t varied[12];
    unsigned kept = 0u;

    double variety_total = 0.0;
    unsigned variety_count = 0u;

    while (index < taken)
    {
        size_t run = index + 1u;
        size_t followers = 1u;

        while ((run < taken) && (links[run].stamp == links[index].stamp))
        {
            if (links[run].next != links[run - 1u].next)
            {
                followers++;
            }
            run++;
        }

        const size_t seen = run - index;

        if (seen >= 24u)
        {
            const double variety = (double)followers / (double)seen;

            variety_total += variety;
            variety_count++;

            if (kept < 12u)
            {
                best[kept] = links[index];
                score[kept] = variety;
                counted[kept] = seen;
                varied[kept] = followers;
                kept++;
            }
            else
            {
                unsigned worst = 0u;

                for (unsigned slot = 1u; slot < 12u; slot++)
                {
                    if (score[slot] > score[worst])
                    {
                        worst = slot;
                    }
                }
                if (variety < score[worst])
                {
                    best[worst] = links[index];
                    score[worst] = variety;
                    counted[worst] = seen;
                    varied[worst] = followers;
                }
            }
        }
        index = run;
    }

    for (unsigned slot = 0u; slot < kept; slot++)
    {
        unsigned pick = slot;

        for (unsigned other = slot + 1u; other < kept; other++)
        {
            if (score[other] < score[pick])
            {
                pick = other;
            }
        }

        const AbLink held = best[slot];
        const double swap = score[slot];
        const size_t swap_seen = counted[slot];
        const size_t swap_varied = varied[slot];

        best[slot] = best[pick];
        score[slot] = score[pick];
        counted[slot] = counted[pick];
        varied[slot] = varied[pick];
        best[pick] = held;
        score[pick] = swap;
        counted[pick] = swap_seen;
        varied[pick] = swap_varied;

        printf("#   %-18.*s %-8u %-10u %.3f\n", (int)best[slot].span, &corpus[best[slot].where],
               (unsigned)counted[slot], (unsigned)varied[slot], score[slot]);
    }

    printf("ancorae_formula,%s,%u,%u,%.4f\n", name, (unsigned)taken, variety_count,
           (variety_count > 0u) ? (variety_total / (double)variety_count) : 0.0);
}

static int ab_by_place(const void *left, const void *right)
{
    const AbLink *const one = (const AbLink *)left;
    const AbLink *const other = (const AbLink *)right;

    if (one->stamp != other->stamp)
    {
        return (one->stamp < other->stamp) ? -1 : 1;
    }
    if (one->where != other->where)
    {
        return (one->where < other->where) ? -1 : 1;
    }
    return 0;
}

static void ab_salience(const char *name, const uint8_t *corpus, size_t corpus_len, uint8_t marker)
{
    static AbLink places[AB_TOKEN_BUDGET];
    size_t taken = 0u;
    size_t at = 0u;

    while ((at < corpus_len) && (taken < AB_TOKEN_BUDGET))
    {
        while ((at < corpus_len) && (corpus[at] == marker))
        {
            at++;
        }

        const size_t opened = at;
        uint64_t stamp = 1469598103934665603uLL;

        while ((at < corpus_len) && (corpus[at] != marker))
        {
            stamp ^= (uint64_t)corpus[at];
            stamp *= 1099511628211uLL;
            at++;
        }
        if (at > opened)
        {
            places[taken].stamp = stamp;
            places[taken].next = (uint64_t)taken;
            places[taken].where = (uint32_t)opened;
            places[taken].span = (uint32_t)(at - opened);
            taken++;
        }
    }

    if (taken < 1024u)
    {
        return;
    }

    qsort(places, taken, sizeof places[0], ab_by_place);

    AbLink best[10];
    double score[10];
    size_t counted[10];
    unsigned kept = 0u;
    size_t index = 0u;

    while (index < taken)
    {
        size_t run = index + 1u;

        while ((run < taken) && (places[run].stamp == places[index].stamp))
        {
            run++;
        }

        const size_t seen = run - index;

        if (seen >= 24u)
        {
            double total = 0.0;
            double squares = 0.0;

            for (size_t step = index + 1u; step < run; step++)
            {
                const double apart = (double)places[step].next - (double)places[step - 1u].next;

                total += apart;
                squares += apart * apart;
            }

            const double runs = (double)(seen - 1u);
            const double mean = total / runs;
            const double spread = (squares / runs) - (mean * mean);
            const double burst = (mean > 0.0) ? (spread / (mean * mean)) : 0.0;

            if (kept < 10u)
            {
                best[kept] = places[index];
                score[kept] = burst;
                counted[kept] = seen;
                kept++;
            }
            else
            {
                unsigned worst = 0u;

                for (unsigned slot = 1u; slot < 10u; slot++)
                {
                    if (score[slot] < score[worst])
                    {
                        worst = slot;
                    }
                }
                if (burst > score[worst])
                {
                    best[worst] = places[index];
                    score[worst] = burst;
                    counted[worst] = seen;
                }
            }
        }
        index = run;
    }

    printf("# %s, burst\n", name);
    for (unsigned slot = 0u; slot < kept; slot++)
    {
        unsigned pick = slot;

        for (unsigned other = slot + 1u; other < kept; other++)
        {
            if (score[other] > score[pick])
            {
                pick = other;
            }
        }

        const AbLink held = best[slot];
        const double swap = score[slot];
        const size_t swap_seen = counted[slot];

        best[slot] = best[pick];
        score[slot] = score[pick];
        counted[slot] = counted[pick];
        best[pick] = held;
        score[pick] = swap;
        counted[pick] = swap_seen;

        printf("#   %-18.*s %-8u %.2f\n", (int)best[slot].span, &corpus[best[slot].where],
               (unsigned)counted[slot], score[slot]);
    }
}

static size_t ab_rarest(const uint8_t *needle, size_t length)
{
    size_t best = 0u;
    unsigned best_cost = 256u;

    for (size_t index = 0u; index < length; index++)
    {
        const unsigned cost = (unsigned)EMBED_CALL(ancorae.impensa, AncoraeCfg, .byte = needle[index]);

        if (cost < best_cost)
        {
            best_cost = cost;
            best = index;
        }
    }
    return best;
}

static size_t ab_salted_offset(size_t length, uint64_t salt)
{
    uint8_t seed[8];
    uint8_t digest[MMGR_SHA256_BYTES];

    for (unsigned index = 0u; index < 8u; index++)
    {
        seed[index] = (uint8_t)((salt >> (56u - (index * 8u))) & 0xFFu);
    }
    mmgr_sha256(seed, sizeof seed, digest);

    const uint32_t drawn = ((uint32_t)digest[0] << 24) | ((uint32_t)digest[1] << 16) |
                           ((uint32_t)digest[2] << 8) | (uint32_t)digest[3];

    return (size_t)(drawn % (uint32_t)length);
}

static void ab_report(const char *name, const uint8_t *corpus, size_t corpus_len, size_t needle_len)
{
    if (needle_len >= (corpus_len / 4u))
    {
        return;
    }

    double frequency[256];
    uint32_t counts[256];

    for (unsigned byte = 0u; byte < 256u; byte++)
    {
        counts[byte] = 0u;
    }
    for (size_t index = 0u; index < corpus_len; index++)
    {
        counts[corpus[index]]++;
    }
    for (unsigned byte = 0u; byte < 256u; byte++)
    {
        frequency[byte] = (double)counts[byte] / (double)corpus_len;
    }

    double collision = 0.0;

    for (unsigned byte = 0u; byte < 256u; byte++)
    {
        collision += frequency[byte] * frequency[byte];
    }

    const double renyi = -log2(collision);
    const double covers = (renyi > 0.0) ? (log2((double)needle_len * renyi * log(2.0)) / renyi) : 1.0;
    size_t free_stride = (covers > 0.0) ? (size_t)(((double)needle_len / covers) + 0.5) : needle_len;

    if (free_stride < 1u)
    {
        free_stride = 1u;
    }

    const double alignments = (double)((corpus_len - needle_len) + 1u);
    const double covers_unique = (renyi > 0.0) ? (log2(alignments) / renyi) : 1.0;
    size_t unique_stride = (covers_unique > 0.0) ? (size_t)(((double)needle_len / covers_unique) + 0.5) : 1u;

    if (unique_stride < 1u)
    {
        unique_stride = 1u;
    }

    double unique_reads = 0.0;
    unsigned unique_wrong = 0u;
    unsigned unique_over = 0u;

    uint64_t mirror_error = 0u;

    const size_t step = (corpus_len - needle_len) / AB_SAMPLES;

    double totals[12] = {0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0};
    uint64_t worst[12] = {0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u};
    size_t free_depth = 0u;

    double distance_value[AB_MAX_NEEDLE];
    double steered_value[AB_MAX_NEEDLE];

    for (size_t offset = 0u; offset < needle_len; offset++)
    {
        distance_value[offset] = (double)(offset + 1u);
        steered_value[offset] = (double)(offset + 1u);
    }

    uint32_t carried[256];

    for (unsigned byte = 0u; byte < 256u; byte++)
    {
        carried[byte] = 1u;
    }
    double chosen_offset = 0.0;
    unsigned samples = 0u;
    unsigned disagreed = 0u;

    for (size_t sample = 0u; sample < AB_SAMPLES; sample++)
    {
        const uint8_t *const needle = &corpus[sample * step];
        const size_t rare = ab_rarest(needle, needle_len);
        const size_t salted = ab_salted_offset(needle_len, 0xA5A5u + (uint64_t)sample);
        const size_t ideal = ab_best_anchor(needle, needle_len, frequency);

        const AbResult arms[12] = {
            ab_naive(corpus, corpus_len, needle, needle_len),
            ab_kmp(corpus, corpus_len, needle, needle_len),
            ab_anchored(corpus, corpus_len, needle, needle_len, needle_len - 1u),
            ab_anchored(corpus, corpus_len, needle, needle_len, rare),
            ab_anchored(corpus, corpus_len, needle, needle_len, salted),
            ab_horspool_rare(corpus, corpus_len, needle, needle_len, rare),
            ab_anchored(corpus, corpus_len, needle, needle_len, ideal),
            ab_interrogative(corpus, corpus_len, needle, needle_len, NULL),
            ab_interrogative(corpus, corpus_len, needle, needle_len, carried),
            ab_distance_only(corpus, corpus_len, needle, needle_len, distance_value, 0u, 0u, 0.1, 0.0, 0.0),
            ab_distance_only(corpus, corpus_len, needle, needle_len, steered_value, 0u, 0u, 0.35, 0.05, -1.0),
            ab_free_order(corpus, corpus_len, needle, needle_len, free_stride, &free_depth, 1u, &mirror_error),
        };

        size_t unique_depth = 0u;
        const AbResult unique =
            ab_free_order(corpus, corpus_len, needle, needle_len, unique_stride, &unique_depth, 0u,
                          &mirror_error);

        unique_reads += (double)unique.reads;
        if (unique.found != arms[0].found)
        {
            unique_wrong++;
            if (unique.found > arms[0].found)
            {
                unique_over++;
            }
        }

        chosen_offset += (double)ideal;

        unsigned agreed = 1u;

        for (unsigned which = 1u; which < 12u; which++)
        {
            if (arms[which].found != arms[0].found)
            {
                agreed = 0u;
            }
        }
        if (agreed == 0u)
        {
            disagreed++;
            continue;
        }

        for (unsigned which = 0u; which < 12u; which++)
        {
            totals[which] += (double)arms[which].reads;
            if (arms[which].reads > worst[which])
            {
                worst[which] = arms[which].reads;
            }
        }
        samples++;
    }

    if (samples == 0u)
    {
        return;
    }

    const double count = (double)samples;

    const uint8_t *const calibrator = &corpus[0];
    const uint32_t calibrator_truth = ab_naive(corpus, corpus_len, calibrator, needle_len).found;
    size_t low = 1u;
    size_t high = needle_len;
    double calibration_reads = 0.0;

    while (low < high)
    {
        const size_t middle = low + (((high - low) + 1u) / 2u);
        size_t reached = 0u;
        const AbResult trial =
            ab_free_order(corpus, corpus_len, calibrator, needle_len, middle, &reached, 0u, &mirror_error);

        calibration_reads += (double)trial.reads;
        if (trial.found == calibrator_truth)
        {
            low = middle;
        }
        else
        {
            high = middle - 1u;
        }
    }

    const size_t calibrated_stride = low;
    double calibrated_reads = 0.0;
    unsigned calibrated_wrong = 0u;
    unsigned calibrated_tried = 0u;

    for (size_t sample = 1u; sample < AB_SAMPLES; sample++)
    {
        const uint8_t *const needle = &corpus[sample * step];
        size_t reached = 0u;
        const AbResult held =
            ab_free_order(corpus, corpus_len, needle, needle_len, calibrated_stride, &reached, 0u,
                          &mirror_error);

        calibrated_reads += (double)held.reads;
        if (held.found != ab_naive(corpus, corpus_len, needle, needle_len).found)
        {
            calibrated_wrong++;
        }
        calibrated_tried++;
    }

    double adaptive_reads = 0.0;
    double adaptive_probes = 0.0;
    unsigned adaptive_wrong = 0u;

    for (size_t sample = 0u; sample < AB_SAMPLES; sample++)
    {
        const uint8_t *const needle = &corpus[sample * step];
        size_t used = 0u;
        const AbResult held = ab_adaptive(corpus, corpus_len, needle, needle_len, &used, &mirror_error);

        adaptive_reads += (double)held.reads;
        adaptive_probes += (double)used;
        if (held.found != ab_naive(corpus, corpus_len, needle, needle_len).found)
        {
            adaptive_wrong++;
        }
    }

    printf("ancorae_adaptive,%s,%u,%u,%.1f,%.1f,%.1f,%u,%.3f\n", name, (unsigned)needle_len,
           (unsigned)corpus_len, totals[2] / count, adaptive_reads / (double)AB_SAMPLES,
           adaptive_probes / (double)AB_SAMPLES, adaptive_wrong,
           (adaptive_reads > 0.0) ? (totals[2] / count / (adaptive_reads / (double)AB_SAMPLES)) : 0.0);

    printf("ancorae_mirror,%s,%u,%u,%llu,%s\n", name, (unsigned)needle_len, (unsigned)corpus_len,
           (unsigned long long)mirror_error, (mirror_error == 0u) ? "exact" : "BROKEN");

    printf("ancorae_calib,%s,%u,%u,%u,%u,%.1f,%.1f,%u,%u,%.2f\n", name, (unsigned)needle_len,
           (unsigned)corpus_len, (unsigned)calibrated_stride, (unsigned)unique_stride,
           calibration_reads, calibrated_reads / (double)calibrated_tried, calibrated_wrong,
           calibrated_tried, (calibrated_reads > 0.0) ? (totals[2] / count / (calibrated_reads / (double)calibrated_tried)) : 0.0);

    printf("ancorae_ab,%s,%u,%u,%u,"
           "%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,"
           "%.1f,%u,%u,%u,%.4f,%s\n",
           name,
           (unsigned)needle_len, (unsigned)corpus_len, samples, totals[0] / count, totals[1] / count, totals[2] / count,
           totals[3] / count, totals[4] / count, totals[5] / count, totals[6] / count, totals[7] / count,
           totals[8] / count, totals[9] / count, totals[10] / count, totals[11] / count,
           unique_reads / count, (unsigned)unique_stride, unique_wrong, unique_over,
           (unique_reads > 0.0) ? (totals[2] / unique_reads) : 0.0,
           (disagreed == 0u) ? "agree" : "BROKEN");
}

static size_t ab_fill_mixed(uint8_t *into, size_t length)
{
    const size_t region = length / 4u;

    ab_fill_text(&into[0], s_ab_prose, region);
    ab_fill_text(&into[region], s_ab_source, region);
    ab_fill_periodic(&into[region * 2u], region);
    ab_fill_uniform(&into[region * 3u], region);

    return region * 4u;
}

int main(int argc, char **argv)
{
    if (argc > 1)
    {
        static uint8_t held[AB_FILE_BYTES];

        printf("bench,corpus,corpus_bytes,tightest_byte,mean_gap,dispersion,shuffled_byte,"
               "shuffled_dispersion,ratio\n");
        printf("bench,corpus,corpus_bytes,units,distinct,mean_unit,zipf_slope,brevity_correlation\n");

        for (int which = 1; which < argc; which++)
        {
            FILE *const source = fopen(argv[which], "rb");

            if (source == NULL)
            {
                printf("# cannot open %s\n", argv[which]);
                continue;
            }

            const size_t taken = fread(held, 1u, sizeof held, source);

            (void)fclose(source);

            for (size_t index = 0u; index < taken; index++)
            {
                if ((held[index] == 0x0Du) || (held[index] == 0x0Au))
                {
                    held[index] = 0x20u;
                }
            }
            if (taken < 1024u)
            {
                printf("# %s too short at %u bytes\n", argv[which], (unsigned)taken);
                continue;
            }

            const char *label = argv[which];

            for (const char *walk = argv[which]; *walk != '\0'; walk++)
            {
                if ((*walk == '/') || (*walk == '\\'))
                {
                    label = walk + 1;
                }
            }

            unsigned marker = 0u;
            double gap = 0.0;

            (void)ab_spacing(held, taken, &marker, &gap);
            ab_language(label, held, taken);
            ab_universals(label, held, taken, (uint8_t)marker);
            ab_variety(label, held, taken, (uint8_t)marker);
            ab_salience(label, held, taken, (uint8_t)marker);
        }
        return 0;
    }

    const size_t english_len = ab_fill_text(s_ab_english, s_ab_prose, AB_CORPUS_BYTES);
    const size_t structured_len = ab_fill_text(s_ab_structured, s_ab_source, AB_CORPUS_BYTES);
    const size_t periodic_len = ab_fill_periodic(s_ab_periodic, AB_CORPUS_BYTES);

    ab_fill_uniform(s_ab_uniform, AB_CORPUS_BYTES);

    const size_t mixed_len = ab_fill_mixed(s_ab_mixed, AB_CORPUS_BYTES);

    printf("bench,corpus,needle_len,corpus_bytes,samples,naive,kmp,horspool,rare_anchor,salted_anchor,horspool_rare,"
           "product_rule,interrogative_cold,interrogative_warm,distance_field,distance_field_steered,"
           "free_order,unconfirmed,unique_stride,unconfirmed_wrong,unconfirmed_over,"
           "horspool_over_unconfirmed,check\n");
    printf("bench,corpus,needle_len,corpus_bytes,calibrated_stride,derived_stride,calibration_reads,"
           "reads_per_search,wrong,tried,horspool_over_calibrated\n");
    printf("bench,corpus,needle_len,corpus_bytes,horspool,adaptive_reads,adaptive_probes,wrong,"
           "horspool_over_adaptive\n");
    printf("bench,corpus,needle_len,corpus_bytes,mirror_residual,verdict\n");
    printf("bench,corpus,corpus_bytes,collision,shifts_real,shifts_shuffled,strongest_shift,"
           "peak_real,peak_shuffled\n");

    printf("bench,corpus,corpus_bytes,tightest_byte,mean_gap,dispersion,shuffled_byte,"
           "shuffled_dispersion,ratio\n");

    ab_language("english", s_ab_english, english_len);
    ab_language("structured", s_ab_structured, structured_len);
    ab_language("periodic16", s_ab_periodic, periodic_len);
    ab_language("uniform", s_ab_uniform, AB_CORPUS_BYTES);
    ab_language("mixed", s_ab_mixed, mixed_len);

    printf("bench,corpus,corpus_bytes,units,distinct,mean_unit,zipf_slope,brevity_correlation\n");

    ab_universals("english", s_ab_english, english_len, 0x20u);
    ab_universals("structured", s_ab_structured, structured_len, 0x20u);
    ab_universals("periodic16", s_ab_periodic, periodic_len, 0x0Au);
    ab_universals("uniform", s_ab_uniform, AB_CORPUS_BYTES, 0x45u);
    ab_universals("mixed", s_ab_mixed, mixed_len, 0x20u);

    printf("bench,corpus,needle_len,corpus_bytes,markers,marks_in_needle,survivors,reduction,"
           "marker_rate\n");

    static const size_t marked_lengths[] = {16u, 32u, 64u, 128u, 256u};

    for (size_t index = 0u; index < (sizeof marked_lengths / sizeof marked_lengths[0]); index++)
    {
        ab_boundary_filter("english", s_ab_english, english_len, marked_lengths[index], 0x20u);
        ab_boundary_filter("structured", s_ab_structured, structured_len, marked_lengths[index], 0x3Bu);
        ab_boundary_filter("periodic16", s_ab_periodic, periodic_len, marked_lengths[index], 0x0Au);
        ab_boundary_filter("uniform", s_ab_uniform, AB_CORPUS_BYTES, marked_lengths[index], 0x45u);
    }

    ab_discover("english", s_ab_english, english_len);
    ab_discover("structured", s_ab_structured, structured_len);
    ab_discover("periodic16", s_ab_periodic, periodic_len);
    ab_discover("uniform", s_ab_uniform, AB_CORPUS_BYTES);
    ab_discover("mixed", s_ab_mixed, mixed_len);

    static const size_t lengths[] = {4u, 8u, 16u, 32u, 64u, 128u, 256u};

    for (size_t index = 0u; index < (sizeof lengths / sizeof lengths[0]); index++)
    {
        ab_report("english", s_ab_english, english_len, lengths[index]);
        ab_report("structured", s_ab_structured, structured_len, lengths[index]);
        ab_report("periodic16", s_ab_periodic, periodic_len, lengths[index]);
        ab_report("uniform", s_ab_uniform, AB_CORPUS_BYTES, lengths[index]);
        ab_report("mixed", s_ab_mixed, mixed_len, lengths[index]);
    }
    return 0;
}
