/* MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_ancorae_ab.c
 * @brief The rare anchor against the classical search algorithms, on one corpus, one needle set, and
 *        one counter.
 * @author dstroy0 (Douglas Quigg (dstroy0)) <dquigg123@gmail.com>
 * @date 2026-09-01
 *
 * @note What this settles. The sift bench measures how many candidates an anchor admits, which says
 *       nothing about how a whole search compares to one built a different way. Reducing candidates
 *       and reducing work are not the same objective, and a filter can win the first and lose the
 *       second.
 * @note The tradeoff being measured, stated before the numbers so it cannot be discovered afterward.
 *       A failed anchor at pattern offset a lets the pattern advance until some earlier pattern
 *       position carries the byte that was read, and past the cell entirely when none does. The
 *       largest advance available is therefore a+1. Horspool anchors at m-1, the largest offset a
 *       pattern has, so it has the longest possible advance and the worst possible candidate rate.
 *       Anchoring at the rarest byte takes the best candidate rate and gives up advance in exchange.
 *       Which one wins is arithmetic over a corpus and is not obvious from either property alone.
 * @note The counter is corpus symbol accesses. Every algorithm reads cells out of the same corpus and
 *       that is the resource they share, so counting reads compares the algorithms instead of
 *       comparing their inner loops. No timing appears here and no row is a performance claim.
 * @warning Every algorithm below is written here, so a defect in one would show as a result. All of
 *          them are held to the occurrence set that a brute force scan finds, and a row that
 *          disagrees prints BROKEN and is not a number to read.
 */
#include "impensa_ancorae_acus/impensa_ancorae_acus.h"

// The uniform corpus comes out of this. Held to RFC 6234's vectors by its own self test
#include "mmgr_sha256.h"

#include <math.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/**
 * @brief Bytes in each corpus.
 */
#define AB_CORPUS_BYTES 4096u

/**
 * @brief How many needles are drawn from each corpus at each length.
 */
#define AB_SAMPLES 64u

/**
 * @brief The longest needle any algorithm here is given.
 */
#define AB_MAX_NEEDLE 256u

/**
 * @brief The most bytes read from a corpus named on the command line.
 *
 * @note The built in corpora are a few kilobytes because the search arms sweep them many times over.
 *       A file given on the command line is only measured for its boundary and its unit statistics,
 *       which is one pass, so it can be far larger and needs to be: a claim about what every language
 *       does is not testable on a few hundred words.
 */
#define AB_FILE_BYTES (1u << 20)

/**
 * @brief The most units a corpus named on the command line is split into.
 */
#define AB_FILE_UNITS (1u << 18)

/**
 * @brief How many units a vocabulary comparison is allowed to see.
 *
 * @note Vocabulary grows with text length, so counting distinct units over whole corpora of different
 *       sizes compares the sizes as much as the languages. Every corpus is cut to the same number of
 *       units before its vocabulary is counted, and the number is small enough that the shortest text
 *       in the set still reaches it.
 */
#define AB_TOKEN_BUDGET 25000u

/**
 * @brief What one algorithm did on one needle.
 *
 * @note Both fields matter and for different reasons. @c reads is the measurement. @c found is the
 *       check, because an algorithm that reads fewer cells and misses occurrences has not won
 *       anything.
 */
typedef struct
{
    uint64_t reads;
    uint32_t found;
} AbResult;

static uint8_t s_ab_english[AB_CORPUS_BYTES];
static uint8_t s_ab_structured[AB_CORPUS_BYTES];
static uint8_t s_ab_periodic[AB_CORPUS_BYTES];
static uint8_t s_ab_uniform[AB_CORPUS_BYTES];

/**
 * @brief Four regions of a thousand bytes each, laid end to end.
 *
 * @note The case every other corpus here fails to be. English, then C source, then fixed width
 *       records, then uniform bytes, so a search crosses three boundaries and anything it learned
 *       about one region is wrong in the next. A field accumulated over the whole thing describes no
 *       part of it, which is the only condition under which discarding the field can pay.
 */
static uint8_t s_ab_mixed[AB_CORPUS_BYTES];

/**
 * @brief English prose, repeated only as far as the corpus needs and never wrapped.
 */
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
    "that marked the dust and then steadily, so that within a quarter of an hour the whole valley "
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

/**
 * @brief C source, a narrow alphabet with heavy repetition of a few identifiers.
 */
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

/**
 * @brief Copies text into a corpus without repeating it.
 *
 * @param[out] into   Corpus to fill [BORROWS].
 * @param[in]  text   Text to copy [BORROWS].
 * @param[in]  length Capacity.
 * @return            Bytes written.
 */
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

/**
 * @brief Fills a corpus with 16 byte records whose layout repeats and whose content does not.
 *
 * @param[out] into   Corpus to fill [BORROWS].
 * @param[in]  length Capacity.
 * @return            Bytes written.
 */
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
            // Explicit cast narrows the mixed value to the letter it selects, inside 'a' to 'z'
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

/**
 * @brief Fills a corpus with SHA-256 counter mode output.
 *
 * @param[out] into   Corpus to fill [BORROWS].
 * @param[in]  length Capacity.
 */
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
            // Explicit cast narrows one byte out of the counter, most significant first
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

/**
 * @brief Finds every occurrence by comparing at every position.
 *
 * @param[in] corpus     Bytes to search [BORROWS].
 * @param[in] corpus_len How many.
 * @param[in] needle     What to find [BORROWS].
 * @param[in] needle_len Bytes in it.
 * @return               Reads performed and occurrences found.
 * @note The reference. Its occurrence count is what every other algorithm here is checked against, so
 *       it is written to be obviously right instead of to be quick.
 */
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

/**
 * @brief Finds every occurrence by Knuth Morris Pratt.
 *
 * @param[in] corpus     Bytes to search [BORROWS].
 * @param[in] corpus_len How many.
 * @param[in] needle     What to find [BORROWS].
 * @param[in] needle_len Bytes in it.
 * @return               Reads performed and occurrences found.
 * @note Reads every corpus cell exactly once and never goes back, so its read count is the corpus
 *       length whatever the data does. That makes it the flat line the other algorithms are read
 *       against: anything above it is doing worse than one pass, and anything below it is skipping
 *       cells that KMP is obliged to look at.
 */
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

/**
 * @brief Finds every occurrence by an anchored bad character shift.
 *
 * @param[in] corpus     Bytes to search [BORROWS].
 * @param[in] corpus_len How many.
 * @param[in] needle     What to find [BORROWS].
 * @param[in] needle_len Bytes in it.
 * @param[in] anchor     Which pattern offset to test and shift from.
 * @return               Reads performed and occurrences found.
 * @note One routine covers both arms of this bench, and the anchor is the only thing that differs.
 *       At anchor = needle_len - 1 this is Horspool. At the offset the cost table likes best it is
 *       the arrangement this study argues for. Writing them as one function means a difference in the
 *       rows cannot come from a difference in the code.
 * @note The advance is the smallest step that brings a pattern position carrying the byte just read
 *       onto the cell it was read from, and anchor + 1 when the pattern has no such position before
 *       the anchor. That is the largest advance the read justifies, so the ceiling on it is
 *       anchor + 1 and an anchor in the middle of the pattern gives up advance it cannot recover.
 */
static AbResult ab_anchored(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle, size_t needle_len,
                            size_t anchor)
{
    size_t advance[256];
    AbResult result = {0u, 0u};

    for (unsigned byte = 0u; byte < 256u; byte++)
    {
        advance[byte] = anchor + 1u;
    }
    // Nearest pattern position at or before the anchor carrying each byte. Walking upward leaves the
    // closest one in place, which is the smallest advance and therefore the only safe one
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

/**
 * @brief Finds every occurrence by shifting from the last position and filtering on the rarest.
 *
 * @param[in] corpus     Bytes to search [BORROWS].
 * @param[in] corpus_len How many.
 * @param[in] needle     What to find [BORROWS].
 * @param[in] needle_len Bytes in it.
 * @param[in] rare       Offset of the byte the cost table likes best.
 * @return               Reads performed and occurrences found.
 * @note The arrangement the other arms leave untested. Shift distance and candidate rate are two
 *       different objectives and the anchored arms each pick one: the last position gives the longest
 *       advance a read can justify, and the rarest byte admits the fewest candidates. Neither
 *       excludes the other. This shifts from the last position and spends one extra read on the
 *       rarest byte before committing to a full compare.
 */
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

        // One read on the rarest byte before the full compare. It costs a read whenever the last
        // position already agreed, and saves the rest of the compare whenever it disagrees
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

/**
 * @brief Returns the anchor offset with the largest expected advance, given the corpus frequencies.
 *
 * @param[in] needle     Bytes to choose from [BORROWS].
 * @param[in] length     How many.
 * @param[in] frequency  Corpus frequency per byte value, summing to one [BORROWS].
 * @return               The offset maximizing the expected advance per read.
 * @note What the two fixed rules each get half of. A read at offset a advances the search by the
 *       distance to the nearest earlier pattern position carrying the byte that was read, capped at
 *       a + 1, and it advances by one when the byte matches and a compare has to run. The value of an
 *       anchor is that advance averaged over what the corpus actually emits, which is a product of how
 *       often the read rejects and how far a rejection carries. The last position maximizes the cap
 *       and ignores the frequencies. The rarest byte maximizes the rejection rate and ignores the cap.
 * @note The frequencies come from the corpus and not from a table compiled into the binary. On a
 *       corpus with no rare byte every offset rejects equally often, the product is decided by the cap
 *       alone, and this returns the last position. The rule collapses onto Horspool exactly where
 *       Horspool is the right answer.
 * @warning This reads the whole corpus's frequencies before searching, so it is a ceiling on what any
 *          anchor rule can do and not a proposal for how to compute one. What it costs to learn those
 *          frequencies is not counted here.
 */
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
        // A read that agrees runs a compare and moves on by one, so it earns the least of any outcome
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

/**
 * @brief Finds every occurrence without choosing an anchor in advance.
 *
 * @param[in] corpus     Bytes to search [BORROWS].
 * @param[in] corpus_len How many.
 * @param[in] needle     What to find [BORROWS].
 * @param[in] needle_len Bytes in it.
 * @return               Reads performed and occurrences found.
 * @note Every other arm here decides where to read before it has read anything, from a table compiled
 *       into the binary or from a histogram obtained some other way. This one holds no prior and asks.
 *       It reads, evaluates what the answer rules out, records what came back, and lets the answers so
 *       far decide where to read next. The frequencies are never supplied because the corpus emits
 *       them, and the reads that carry them had to happen anyway.
 * @note The starting state is a flat count over every byte value, which is the state of knowing
 *       nothing. Under a flat estimate every value rejects equally often, the expected advance is
 *       decided by the cap alone, and the best offset is the last one. So this begins as Horspool
 *       without being told to and moves away from it only as the corpus gives it a reason.
 * @note The anchor is reconsidered once every needle_len reads. Reconsidering on every read costs
 *       arithmetic that this bench does not count, and pretending otherwise would flatter it.
 */
static AbResult ab_interrogative(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle, size_t needle_len,
                                 uint32_t *carried)
{
    uint32_t local_count[256];
    uint32_t *const seen_count = (carried != NULL) ? carried : local_count;
    double estimate[256];
    size_t advance[256];
    AbResult result = {0u, 0u};

    // A flat prior, which is one observation of every value and no knowledge of the corpus. A carried
    // array skips this, because a corpus searched a second time has not changed its frequencies and
    // throwing away what the first search was told would be answering the same question twice
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
                    // Bytes read during a compare are answers too, so they count toward the estimate
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

/**
 * @brief Finds every occurrence while holding no model of the alphabet at all.
 *
 * @param[in] corpus     Bytes to search [BORROWS].
 * @param[in] corpus_len How many.
 * @param[in] needle     What to find [BORROWS].
 * @param[in] needle_len Bytes in it.
 * @param[in] carried    Running advance per offset kept between searches, or NULL to start cold
 *                       [BORROWS].
 * @return               Reads performed and occurrences found.
 * @note Why this holds no counts. Every other adaptive arm here estimates a frequency per symbol,
 *       which needs the alphabet to be finite and enumerable. A domain whose symbols cannot be
 *       enumerated has no such table and never will, however long it is observed. What can still be
 *       observed is the distance an answer carried, because a distance is a count of positions and
 *       stays finite whatever the alphabet does. So this measures the distance directly and never
 *       forms the distribution it would otherwise have been derived from.
 * @note The state is one running distance per candidate offset, which is needle_len numbers. The
 *       symbol side of the problem does not appear.
 * @note Where the starting value comes from. An answer read at offset a can advance the search by at
 *       most a + 1, since beyond that the pattern has left the cell behind and the read says nothing
 *       about where it lands. That bound is a fact about the geometry and not a guess about the data,
 *       so every offset starts at its own ceiling and can only be revised downward. The largest
 *       ceiling is the last offset, so the search opens as Horspool and gives up ground only where an
 *       answer has shown the ceiling to be out of reach.
 * @note The running value forgets, so an offset that stops paying loses its lead and the search
 *       reconsiders. A corpus that changes character partway through is the case that needs it.
 */
static AbResult ab_distance_only(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle, size_t needle_len,
                                 double *carried, unsigned steer, unsigned pull_to_center, double gain_now,
                                 double gain_history, double gain_trend)
{
    double local_value[AB_MAX_NEEDLE];
    double *const value = (carried != NULL) ? carried : local_value;
    size_t advance[256];
    AbResult result = {0u, 0u};

    // Two means of the same quantity at two speeds. The quick one is what the corpus is paying now and
    // the slow one is what the accumulated field expects, so the quick one falling away from the slow
    // one is the field describing a region the search has already left
    double recent = 0.0;
    double settled = 0.0;
    size_t since_reset = 0u;

    // The ambient advance this corpus is paying, taken across every answer and not per offset. It is
    // the level an answer has to stand out from to count as saying anything
    double background = (double)needle_len / 2.0;

    // The accumulated and trend terms are short lived state about the region the search is standing
    // in, so they start empty on every search even when the field itself is carried
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
            // The provable ceiling for this offset, which is the most an answer there could ever buy
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
        size_t travelled;

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
            travelled = 1u;
        }
        else
        {
            travelled = advance[answer];
        }
        start += travelled;

        // One answer, credited to every offset. What a read at some other offset would have earned
        // from this same cell is decided by where the needle carries the symbol just seen, and that
        // is a property of the needle, so it can be worked out for all of them without a table over
        // symbols. A single backward walk gives the nearest earlier position holding it, which is the
        // advance that offset would have taken, and offsets the needle never carries it before earn
        // their full ceiling. A tenth is slow enough to ignore one unlucky answer and quick enough to
        // notice a corpus that has changed
        size_t previous = needle_len;

        for (size_t offset = 0u; offset < needle_len; offset++)
        {
            const double would_travel =
                (needle[offset] == answer) ? 1.0
                                           : ((previous == needle_len) ? (double)(offset + 1u)
                                                                       : (double)(offset - previous));

            // Three responses to one error and they answer different questions. The immediate term
            // moves on what this answer said. The accumulated term moves on a bias that persists
            // across many answers. The trend term moves on the error changing, which is the only one
            // of the three that can act before a drift has finished happening, and no amount of
            // averaging produces it because an average is what a trend is measured against
            if (gain_trend < 0.0)
            {
                // Filtered against the ambient level instead of against the running estimate. Most
                // answers land where the background already sits and carry nothing, so they are
                // dropped whole and never reach the estimate. An answer far enough off the ambient
                // level is signal, and it is applied at full weight. What is not reinforced settles
                // back to the ceiling it can be proved to have, so a deviation has to keep being paid
                // for to be kept
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
            // Bounded so a long run of one sign cannot drive the accumulated term without limit
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

        recent += 0.30 * ((double)travelled - recent);
        settled += 0.02 * ((double)travelled - settled);
        background += 0.02 * ((double)travelled - background);
        since_reset++;

        // Unassume. The field is an accumulated claim about a corpus, and a corpus that has changed
        // character makes that claim wrong in a way no single offset's value reveals. Every value goes
        // back to the ceiling it can be proved to have, which puts the anchor at the last position and
        // starts the convergence again on whatever is here now. The state of knowing nothing is not a
        // different algorithm, it is this one before any answer has arrived
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
            // Where the mass pulls. Every offset votes with the distance it has been earning, and the
            // anchor goes to the balance point of those votes. It is the same construction as the
            // centroid of the pattern's own points, one level up: a mean of positions weighted by
            // something, needing no metric and no ordering to be well defined. Taking the single best
            // offset instead lets one lucky answer move the anchor, and the balance point does not
            // move until enough answers agree
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

/**
 * @brief Finds every occurrence by reading cells chosen in advance, in no particular order.
 *
 * @param[in]  corpus     Bytes to search [BORROWS].
 * @param[in]  corpus_len How many.
 * @param[in]  needle     What to find [BORROWS].
 * @param[in]  needle_len Bytes in it.
 * @param[in]  stride     Distance between the cells the probing phase reads.
 * @param[out] depth      Receives the longest chain of reads where one had to precede another
 *                        [BORROWS].
 * @return                Reads performed and occurrences found.
 * @note Why the order can be given up. A refutation depends only on the cell that produced it, so the
 *       set of alignments a group of reads rules out is the union of what each rules out separately,
 *       and a union does not care what order it was built in. Every other arm here computes its next
 *       position from the symbol it just read, which makes the reads a chain. The positions here are
 *       fixed before the first one happens, so no read waits on another and the chain has length one.
 * @note What that costs. A greedy shift always jumps to the next position not yet ruled out, which is
 *       the most any single read can buy. A fixed stride reads some cells that a greedy walk would
 *       have skipped. The count below is what that waste amounts to, and the depth beside it is what
 *       it bought.
 * @note The verify phase depends on the probe phase, so the reported depth is two: every probe read is
 *       independent of every other, and every verify read waits only on the probes.
 */
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

    // Every cell this phase reads is picked before any of them is read, so none of them waits on
    // another. A cell at position p speaks about every alignment covering it, and kills the ones whose
    // needle position holds a different symbol
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

    // The mirror. A refutation runs from an observed symbol to the alignments it rules out, and the
    // step back runs from a surviving alignment to the symbol that must have been observed: if
    // alignment s survived a probe at p, then the needle carries corpus[p] at offset p-s. So every
    // survivor reconstructs every observation, and the residual is zero. A nonzero count is an
    // indexing defect in this function, which the occurrence check at the end of a search cannot see.
    //
    // Checked once over the survivors instead of after every probe. The alive array only ever loses
    // entries, so an alignment consistent with the whole probe set is consistent with every prefix of
    // it, and the per step form costs a factor of the probe count for no further coverage.
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

    // What the probing phase left behind, which is the number the model predicts and the one worth
    // seeing when it does not
    *depth = 0u;

    for (size_t start = 0u; start < alignments; start++)
    {
        if (alive[start] == 0u)
        {
            continue;
        }
        (*depth)++;

        // Proposition 1 says every occurrence survives every anchor set, so a survivor set the same
        // size as the occurrence set contains exactly the occurrences and nothing else. Confirming
        // then distinguishes nothing, and it is the only step that costs the needle's whole length
        if (confirm == 0u)
        {
            result.found++;
            continue;
        }

        size_t index = 0u;

        while (index < needle_len)
        {
            // Cells the probing phase already read do not need reading again
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

/**
 * @brief Finds every occurrence by choosing each probe from the answers already received.
 *
 * @param[in]  corpus     Bytes to search [BORROWS].
 * @param[in]  corpus_len How many.
 * @param[in]  needle     What to find [BORROWS].
 * @param[in]  needle_len Bytes in it.
 * @param[out] probes     Receives how many cells the selecting phase read [BORROWS].
 * @param[out] mirror     Accumulates reconstruction failures, which must stay zero [BORROWS].
 * @return                Reads performed and occurrences found.
 * @note What separates this from the fixed stride arms. Those choose every probe position before any
 *       text is read, which is also what the published deterministic sampling does, and a fixed set
 *       has to be derived from the pattern to be safe. This holds no probe set. After each answer it
 *       looks at which alignments are still alive and asks where the next read would do the most.
 * @note Why coverage is the criterion. The symbol about to be read is unknown, so every candidate
 *       position kills the same expected fraction of the alignments it touches. What differs between
 *       positions is how many live alignments they touch at all, so the most informative next read is
 *       the one the surviving candidates overlap on. That quantity is a property of the answers so far
 *       and of nothing else.
 * @note It stops when a read kills nothing, which means the position separated no survivors, and the
 *       survivors are then confirmed. Stopping without confirming is measured in Section 4.9.6 of the
 *       research document and is wrong on most searches.
 */
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
        // How many living alignments each cell carries, from a running count of the living ones to
        // the left of each index
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

        // Every survivor must reproduce every answer already taken, which is the check the occurrence
        // count cannot make
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

/**
 * @brief How many cells the discovery pass reads.
 *
 * @note Every pair of them tests one shift, so k reads carry k(k-1)/2 tests. The read count is what
 *       the corpus is charged and the pair count is what the corpus is asked.
 */
#define AB_DISCOVER_READS 512u

/**
 * @brief Reports the shifts at which a corpus repeats itself, without being told what to look for.
 *
 * @param[in] name       Text naming the corpus.
 * @param[in] corpus     Bytes to examine [BORROWS].
 * @param[in] corpus_len How many.
 * @note Every other measurement in this file is given a needle. This one is not. A shift $d$ is a
 *       hypothesis that the corpus agrees with itself $d$ apart, every pair of read cells whose
 *       positions differ by $d$ is a test of it, and a single disagreement refutes it forever. So the
 *       needle is not one pattern, it is every shift at once, and the reads are shared across all of
 *       them.
 * @note What separates signal from nothing. Under no structure a shift survives $t$ independent tests
 *       with probability $2^{-t H_2}$, so the expected count of surviving shifts follows from the
 *       corpus alone. A shift that survives far past that is not a lucky run, it is the corpus
 *       repeating, and the excess is the detection.
 * @note Positions are drawn from SHA-256 so the pairwise differences cover many shifts. Even spacing
 *       would only ever test multiples of the spacing and would find periods it was built to find.
 */
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
            // Explicit cast narrows one byte out of each 64 bit word, most significant first
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

    // A shift is reported when its agreement rate stands far enough above the collision probability
    // that a run of luck does not reach it. The threshold is not trusted on its own: the tests for one
    // shift share read positions, so they are not independent and a standard error computed as though
    // they were is too small. What the threshold means is fixed below by running the same count over a
    // shuffle of the same bytes
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

/**
 * @brief Counts the shifts a corpus reports and the shifts a shuffle of the same bytes reports.
 *
 * @param[in] name       Text naming the corpus.
 * @param[in] corpus     Bytes to examine [BORROWS].
 * @param[in] corpus_len How many.
 * @note The threshold above rests on tests being independent and they are not, since every read joins
 *       many pairs and one common byte lifts all of its own. So the count it produces means nothing
 *       until something says what the count is on data with no structure to find.
 * @note A shuffle of the same bytes is that something. It holds the byte histogram exactly, which
 *       fixes the collision probability, and destroys every relationship between positions, which is
 *       the only thing a shift can be. Whatever the detector reports there is what it reports on
 *       nothing, and the difference is what it found.
 */
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

/**
 * @brief Returns the most regularly spaced symbol in a corpus, and how regular it is.
 *
 * @param[in]  corpus     Bytes to examine [BORROWS].
 * @param[in]  length     How many.
 * @param[out] which      Receives the byte value found [BORROWS].
 * @param[out] gap        Receives its mean spacing [BORROWS].
 * @return                The smallest dispersion found, or 1.0 when no symbol occurs often enough.
 * @note What this looks for and why it is not another pattern. A language has to mark where one unit
 *       ends and the next begins, by a separator or by a rule, or there are no units and it is not a
 *       language. So something in it recurs at bounded intervals, and bounded intervals are what this
 *       measures.
 * @note The statistic. If a symbol's positions carry no structure, the gaps between them are geometric
 *       and the variance equals the squared mean times one minus the rate, so the ratio of variance to
 *       squared mean sits at one. A separator has bounded unit length, so its gaps are far tighter
 *       than geometric and the ratio falls well below one. The ratio has no units and no scale, so the
 *       same threshold reads the same on any alphabet and any corpus length.
 */
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
        // Too few gaps and the variance is noise. Sixteen is enough for the ratio to mean something
        // and low enough that a rare separator is not missed
        if (counted[byte] < 16u)
        {
            continue;
        }

        const double runs = (double)counted[byte];
        const double mean = total[byte] / runs;
        const double spread = (squares[byte] / runs) - (mean * mean);
        const double dispersion = (mean > 0.0) ? (spread / (mean * mean)) : 1.0;

        // A boundary has to be regular enough to find and irregular enough to say where anything is,
        // which Section 4.12.1 measures: a perfectly regular one fixes the phase of its own period and
        // nothing further. Ruled decoration and padding sit at the bottom of this statistic for that
        // reason, so a candidate below the floor is a ruled line and not a language. Every real
        // boundary measured here sits between 0.21 and 0.41
        if (dispersion < 0.05)
        {
            continue;
        }

        // And it has to be frequent enough to be marking units at all. A symbol appearing once every
        // few hundred bytes can be perfectly regular and still be a page number or a verse marker,
        // because whatever it delimits is not a unit of the language. Sixty four bytes is far above
        // every real boundary measured here, which run from 4.70 to 6.82
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

/**
 * @brief Reports whether a corpus carries a boundary marker, against a shuffle of the same bytes.
 *
 * @param[in] name       Text naming the corpus.
 * @param[in] corpus     Bytes to examine [BORROWS].
 * @param[in] corpus_len How many.
 * @note The shuffle holds every symbol's count and destroys where they sit, so every symbol's gaps in
 *       it are geometric by construction and its dispersion is one. Any corpus whose tightest symbol
 *       is far below its shuffle's is marking something.
 */
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

/**
 * @brief Reports how far a needle's boundary spacing narrows the search on its own.
 *
 * @param[in] name       Text naming the corpus.
 * @param[in] corpus     Bytes to search [BORROWS].
 * @param[in] corpus_len How many.
 * @param[in] needle_len Bytes in the needles drawn from it.
 * @param[in] marker     The boundary symbol Section 4.12 found.
 * @note What is being asked. Once a boundary symbol is known, a corpus is also a sequence of gaps
 *       between its occurrences, and that sequence is shorter than the byte sequence by the mean gap.
 *       A needle carrying $k$ boundaries carries $k-1$ gaps between them, and any true occurrence has
 *       to reproduce that run of gaps exactly. So the run is a filter, and the question is how much it
 *       removes compared with the bytes it is made of.
 * @note Why it might beat the symbols. A boundary symbol is common, so as an anchor it is poor: the
 *       space is near a fifth of English and two of them admit one position in twenty five. The gaps
 *       between them are not independent, which is the property that defeats every product rule in
 *       this document, and here it works the other way: a run of specific gaps is far less likely than
 *       the product of its symbol rates.
 */
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
        // The needle's own boundaries, as offsets inside it
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

        // Every alignment whose boundaries fall at the same offsets. The first boundary anchors the
        // run and the rest are checked against it, so what is compared is the spacing and not the
        // absolute position
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

/**
 * @brief One distinct unit of a corpus, with how long it is and how often it occurs.
 */
typedef struct
{
    uint64_t stamp;
    uint32_t seen;
    uint32_t span;
} AbUnit;

/**
 * @brief Orders units so the most frequent come first.
 *
 * @param[in] left  One unit [BORROWS].
 * @param[in] right The other [BORROWS].
 * @return          Negative, zero or positive as the left belongs before, with, or after the right.
 */
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

/**
 * @brief Orders units by their fingerprint so equal ones sit together.
 *
 * @param[in] left  One unit [BORROWS].
 * @param[in] right The other [BORROWS].
 * @return          Negative, zero or positive as the left belongs before, with, or after the right.
 */
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

/**
 * @brief Reports the two regularities every human language is said to carry, on a corpus split by its
 *        own boundary symbol.
 *
 * @param[in] name       Text naming the corpus.
 * @param[in] corpus     Bytes to examine [BORROWS].
 * @param[in] corpus_len How many.
 * @param[in] marker     The boundary symbol Section 4.12 found.
 * @note What is being tested. Section 4.12 finds where units end, so the spans between markers are
 *       units and nothing here needs a dictionary to say so. Two properties are then claimed to hold
 *       of every natural language and of nothing that is not one. The frequency of a unit falls as
 *       roughly the reciprocal of its rank, which is a slope near minus one on log axes. And the
 *       frequent units are the short ones, which is a negative correlation between length and log
 *       frequency. Neither is something a writer decides.
 * @note Units are grouped by a 64 bit fingerprint instead of by comparing them pairwise, which is a
 *       shortcut and not part of the argument. Two distinct units sharing a fingerprint would be
 *       counted as one, and at these corpus sizes that is unlikely enough to leave the slopes alone.
 */
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

    // Zipf, as the slope of log frequency against log rank over the head of the ranking, where the
    // law is stated to hold and where the counts are large enough to be worth a regression
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

    // Brevity, as the correlation between how long a unit is and how often it occurs. A language is
    // said to make its common units short, so this is expected to be negative
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

    // How much one unit carries. Vocabulary grows with how much text has been read, so counting types
    // over a whole corpus compares corpus sizes as much as languages and the count is taken at a fixed
    // budget instead. The entropy beside it is what a unit is worth in bits, which is the quantity a
    // language packing more description into each word would raise.
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

/**
 * @brief One unit, where it was first seen, and what followed it.
 */
typedef struct
{
    uint64_t stamp;
    uint64_t next;
    uint32_t where;
    uint32_t span;
} AbLink;

/**
 * @brief Orders links by the unit and then by what followed it.
 *
 * @param[in] left  One link [BORROWS].
 * @param[in] right The other [BORROWS].
 * @return          Negative, zero or positive as the left belongs before, with, or after the right.
 */
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

/**
 * @brief Reports the frequent units of a corpus and how varied the company they keep is.
 *
 * @param[in] name       Text naming the corpus.
 * @param[in] corpus     Bytes to examine [BORROWS].
 * @param[in] corpus_len How many.
 * @param[in] marker     The boundary symbol Section 4.12 found.
 * @note Frequency alone cannot tell two kinds of common unit apart. In an English bible `the` and
 *       `God` are both frequent, and one of them is frequent because it attaches to everything while
 *       the other is frequent because the book is about it. What separates them is the company: a unit
 *       that can precede anything has as many distinct followers as it has occurrences, and a unit
 *       belonging to a narrow subject has far fewer.
 * @note So the ratio of distinct followers to occurrences is near one for a unit doing grammatical
 *       work and well below one for a unit doing subject work. Nothing here is given a dictionary, a
 *       part of speech, or a language.
 */
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

    // Walk each unit's run once, counting how often it occurs and how many different units follow it
    printf("# %s\n", name);

    size_t index = 0u;
    AbLink best[12];
    double score[12];
    size_t counted[12];
    size_t varied[12];
    unsigned kept = 0u;

    // Averaged over every unit common enough to measure, this is how much of the text is running to a
    // formula. A text whose frequent units each admit many followers is composing; one whose frequent
    // units admit few is reciting
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

        // Only units common enough for the ratio to mean something, ordered by how narrow their
        // company is
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

/**
 * @brief Orders links by the unit and then by where it occurred.
 *
 * @param[in] left  One link [BORROWS].
 * @param[in] right The other [BORROWS].
 * @return          Negative, zero or positive as the left belongs before, with, or after the right.
 */
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

/**
 * @brief Reports the units a text returns to in bursts, as against the ones it uses throughout.
 *
 * @param[in] name       Text naming the corpus.
 * @param[in] corpus     Bytes to examine [BORROWS].
 * @param[in] corpus_len How many.
 * @param[in] marker     The boundary symbol Section 4.12 found.
 * @note Section 4.14 finds units that keep narrow company, which catches connectives along with
 *       everything else, because a connective attaches to a limited set as readily as a subject word
 *       does. Connectives are the wrong answer for a different reason: they are needed everywhere and
 *       so they say nothing about what a text is about.
 * @note What separates them is where they fall. A unit doing grammatical work is spread evenly through
 *       a text, so the gaps between its occurrences are close to geometric and their dispersion sits
 *       near one. A unit belonging to a subject appears in bursts where that subject is discussed, so
 *       its gaps are far more varied and its dispersion is well above one. That is the statistic of
 *       Section 4.12 read at the other end: low dispersion marks a boundary and high dispersion marks
 *       a subject.
 */
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

/**
 * @brief Returns the offset of the byte the linked cost table likes best.
 *
 * @param[in] needle Bytes to choose from [BORROWS].
 * @param[in] length How many.
 * @return           The offset of the lowest cost byte, ties going to the leftmost.
 */
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

/**
 * @brief Returns an anchor offset drawn from a salt instead of from the data.
 *
 * @param[in] length Bytes in the needle.
 * @param[in] salt   Varies the choice between searches.
 * @return           An offset inside the needle, chosen without looking at it.
 * @note The arm the deterministic rules cannot cover. Rarest, last and first are all functions of the
 *       needle, so an adversary holding the needle knows where the anchor will land and can build a
 *       corpus that defeats it. A salted offset is a function of the salt, and the same needle
 *       searched twice under two salts anchors in two places.
 * @note Drawn from SHA-256 so the choice is reproducible from the salt and carries no structure the
 *       corpus could share.
 */
static size_t ab_salted_offset(size_t length, uint64_t salt)
{
    uint8_t seed[8];
    uint8_t digest[MMGR_SHA256_BYTES];

    for (unsigned index = 0u; index < 8u; index++)
    {
        // Explicit cast narrows one byte out of the salt, most significant first
        seed[index] = (uint8_t)((salt >> (56u - (index * 8u))) & 0xFFu);
    }
    mmgr_sha256(seed, sizeof seed, digest);

    const uint32_t drawn = ((uint32_t)digest[0] << 24) | ((uint32_t)digest[1] << 16) |
                           ((uint32_t)digest[2] << 8) | (uint32_t)digest[3];

    return (size_t)(drawn % (uint32_t)length);
}

/**
 * @brief Runs every algorithm over one corpus at one needle length and reports reads per algorithm.
 *
 * @param[in] name       Text naming the corpus.
 * @param[in] corpus     Bytes to search [BORROWS].
 * @param[in] corpus_len How many.
 * @param[in] needle_len Bytes in the needles drawn from it.
 * @note Every algorithm sees the same corpus and the same needles, and each row carries the check
 *       against the reference occurrence count. A row whose algorithms disagree is a defect and says
 *       nothing about which one is better.
 */
static void ab_report(const char *name, const uint8_t *corpus, size_t corpus_len, size_t needle_len)
{
    if (needle_len >= (corpus_len / 4u))
    {
        return;
    }

    // What the corpus emits, which is the thing a shipped table can only guess at
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

    // The stride the model says is best, from the corpus's own collision probability. Probing every
    // k cells covers each alignment m/k times, and the total of probe reads and surviving
    // verifications is smallest at this k
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

    // The stride that leaves about as many survivors as there are occurrences. Probing that hard costs
    // more probes and removes the confirmation entirely, which is the only step priced at the needle's
    // whole length
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

    // Reconstruction failures across every probe of every arm below. The algebra says this stays zero
    // at every step, so any other value is a defect and not a property of a corpus
    uint64_t mirror_error = 0u;

    const size_t step = (corpus_len - needle_len) / AB_SAMPLES;

    // Five arms: the reference, KMP, and three anchored searches differing only in where the anchor
    // sits. The mean is what a fair corpus rewards and the worst case is where a fixed rule pays for
    // being predictable, so both are carried
    double totals[12] = {0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0};
    uint64_t worst[12] = {0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u};
    size_t free_depth = 0u;

    // The distance only arm's state, carried between searches. One number per offset, each starting at
    // the advance that offset could at most deliver
    double distance_value[AB_MAX_NEEDLE];
    double steered_value[AB_MAX_NEEDLE];

    for (size_t offset = 0u; offset < needle_len; offset++)
    {
        distance_value[offset] = (double)(offset + 1u);
        steered_value[offset] = (double)(offset + 1u);
    }

    // What the warm arm carries between searches. One flat observation each to start, and after that
    // only what the corpus itself has answered
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
            // Amplification for an answer that stands out, settling for one that does not, and a
            // negative trend gain selects that rule in place of the three term one
            ab_distance_only(corpus, corpus_len, needle, needle_len, steered_value, 0u, 0u, 0.35, 0.05, -1.0),
            ab_free_order(corpus, corpus_len, needle, needle_len, free_stride, &free_depth, 1u, &mirror_error),
        };

        // Probed to uniqueness and never confirmed. Its answer is the survivor set itself, so the
        // check is whether that set is the occurrence set and not whether it verified
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

    // Calibration. One needle whose occurrence count is known picks the largest stride that reproduces
    // that count, and every other needle is then searched at it without confirming. The count is
    // monotone in the stride, since a smaller stride only ever probes more, so the largest safe value
    // can be bisected. What this asks is whether a stride calibrated on one pattern is safe for the
    // rest, which no analytic formula in this document can answer because none of them sees the
    // correlation that decides it.
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

    // Adaptive probing, measured on the same needles. It holds no probe set and derives nothing from
    // the pattern in advance, so it is the arrangement neither a fixed stride nor a precomputed sample
    // covers
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
           calibrated_tried, (calibrated_reads > 0.0)
                                 ? (totals[2] / count / (calibrated_reads / (double)calibrated_tried))
                                 : 0.0);

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

/**
 * @brief Lays four regions of a quarter of the corpus each, end to end.
 *
 * @param[out] into   Corpus to fill [BORROWS].
 * @param[in]  length Capacity.
 * @return            Bytes written.
 * @note Each region is filled by the same routine that fills its own corpus, so the mixture is the
 *       four already measured here and not a fifth thing. What changes at a boundary is only which of
 *       them the search is standing in.
 */
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
    // A corpus named on the command line is measured for its boundary and its unit statistics only.
    // Those two are one pass each, so a real text can be used, which the built in corpora are far too
    // small to stand in for when the question is what every language does
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

            // Line endings are the publisher's, not the language's. A plain text file wrapped at a
            // fixed width carries a carriage return every fifty odd bytes, which is more regular than
            // any word boundary, so the detector would find the formatting and report it as the
            // language. Folding both line characters into the space removes that layer and leaves what
            // the writer wrote.
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
        // The boundary symbol each corpus reported in the rows above
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
