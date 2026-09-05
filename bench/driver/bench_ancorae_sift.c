/* MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_ancorae_sift.c
 * @brief What an anchor actually sifts: candidates, skip distance, and whether two anchors are
 *        independent enough for their rates to multiply.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-01
 *
 * @note Counts, not cycles. How many positions survive an anchor over a corpus is a property of the
 *       data and the table, identical on every part, so this reports numbers that are true
 *       everywhere and times nothing. What a SWAR word costs is the other bench and needs a board.
 * @note The question. One anchor admits the positions where its byte occurs. Two anchors at a fixed
 *       stride admit the positions where both occur, and the useful claim is that those rates
 *       multiply. They multiply exactly when the two are independent, and English is not memoryless
 *       - q is followed by u, th and he are enormously overrepresented - so the claim is measured
 *       here rather than assumed.
 * @note The skip is the other half. A rare anchor does not only cut candidates, it means long runs
 *       with no candidate at all, and a search that jumps those runs never touches them. Expected
 *       skip is the corpus length over the occurrence count, and it is what decides whether a sieve
 *       can visit a space it could never enumerate.
 * @warning The cost table is a link time singleton, so a build links exactly one of the five
 *          profiles and this binary can only report on that one. It does not even carry its own
 *          name, which is why every row below is stamped with a fingerprint of the 256 costs.
 *          Comparing profiles means five builds, which is the cost of the current design.
 */
#include "impensa_ancorae_acus/impensa_ancorae_acus.h"

// The control corpus comes out of this, and its uniformity is what every independence number here is
// read against. Held to RFC 6234's vectors by its own self test
#include "mmgr_sha256.h"

#include <math.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>

/**
 * @brief Bytes in each corpus this bench sifts.
 */
#define CORPUS_BYTES 2048u

/**
 * @brief How many needles are drawn from each corpus at each length.
 *
 * @note Drawn from the corpus itself, so every needle is one that genuinely occurs. A needle made up
 *       out of nothing has no occurrences and would report a skip of the whole corpus, which flatters
 *       every anchor equally and measures none of them.
 */
#define NEEDLE_SAMPLES 64u

/**
 * @brief English prose, which is the corpus the english profile was weighted against.
 *
 * @note Ordinary text with ordinary structure: the letter frequencies are Zipf skewed and the
 *       digraphs are correlated, which is exactly the condition the independence question is about.
 */
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
    "that marked the dust and then steadily, so that within a quarter of an hour the whole valley "
    "was grey and the far side of it invisible. they sheltered under an overhanging rock and "
    "watched the water gather in the hollows and run away downhill in a hundred small channels, "
    "each one finding its own way among the stones without any apparent difficulty. it occurred to "
    "him that this was how most problems eventually resolved themselves, given enough time and a "
    "sufficient quantity of water, and he said as much aloud. she laughed and said that was the "
    "sort of remark that sounded wiser than it was, and he had to agree that she was probably "
    "right about that as well. by the time the rain stopped the light was almost gone and they "
    "made camp where they stood rather than risk the descent in darkness. the fire took a long "
    "while to catch because everything was wet, and when it did catch it smoked badly and gave "
    "very little heat, but it was something to sit beside and they were both glad of it. in the "
    "morning the sky had cleared completely and the grass was heavy with water that soaked their "
    "boots within the first few steps. neither of them mentioned the conversation of the previous "
    "evening, though both remembered it, and they walked down toward the village in a silence "
    "that was comfortable rather than awkward. the bakery was already open when they arrived and "
    "the smell of it reached them from a considerable distance up the road, which improved their "
    "mood more than anything either of them could have said. ";

/**
 * @brief The three corpora, filled at startup.
 *
 * @note english is the prose above, repeated to fill. structured is C punctuation and identifiers,
 *       which has a different and much narrower alphabet. uniform stands in for a normal sequence:
 *       every byte equally likely and no correlation between positions, which is the regime where a
 *       weird anchor does not exist and the multiplication is exact.
 * @warning uniform is a surrogate produced by a fixed generator, not the digits of any constant.
 *          Nothing here claims to have hashed pi.
 */
static uint8_t s_english_corpus[CORPUS_BYTES];
static uint8_t s_structured_corpus[CORPUS_BYTES];
static uint8_t s_uniform_corpus[CORPUS_BYTES];
static uint8_t s_periodic_corpus[CORPUS_BYTES];

/**
 * @brief One byte repeated, which is the zero entropy end of the range.
 *
 * @note The opposite limit from uniform. Every position holds every needle, so nothing an anchor does
 *       can remove a candidate and the cost columns have nothing to report. What it is here for is the
 *       invariant: the case with the most occurrences to lose is the case where losing one would show.
 */
static uint8_t s_flat_corpus[CORPUS_BYTES];

/**
 * @brief C source, which is a narrow alphabet with heavy repetition of a few identifiers.
 *
 * @note The other end of the range from prose. Where English has a long tail of rare letters, this
 *       has almost none: a handful of punctuation marks and the same dozen keywords, so the anchor
 *       has much less to work with and the correlation between any two positions is far stronger.
 */
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

/**
 * @brief Fills @p into with @p length bytes of the text at @p text, repeating it.
 *
 * @param[out] into   Corpus to fill [BORROWS].
 * @param[in]  text   Text to repeat [BORROWS].
 * @param[in]  length Bytes to write.
 */
static size_t fill_from_text(uint8_t *into, const char *text, size_t length)
{
    const size_t text_bytes = strlen(text);
    // Never repeats. Repeating to fill made every needle occur once per repetition, and those hits
    // are not false positives - at needle 256 over a 1100 byte text repeated into 4096, nearly all
    // of the reported excess was the corpus matching itself. Measured, and it is why this truncates
    const size_t usable = (text_bytes < length) ? text_bytes : length;

    for (size_t index = 0u; index < usable; index++)
    {
        into[index] = (uint8_t)text[index];
    }
    return usable;
}

/**
 * @brief Bytes in one record of the periodic corpus.
 *
 * @note The claim a coprime stride is supposed to answer needs data with a real period, and prose
 *       and source have none. Fixed width records do: every record starts at a multiple of this.
 */
#define RECORD_BYTES 16u

/**
 * @brief Fills @p into with fixed width records whose layout repeats and whose content does not.
 *
 * @param[out] into   Corpus to fill [BORROWS].
 * @param[in]  length Bytes to write.
 * @return            Bytes written.
 * @note The distinction that makes this a period and not a repetition. A corpus built by repeating
 *       one string is self similar and every needle finds itself, which is the artifact that already
 *       ruined one measurement here. This varies every field per record, so a needle occurs once,
 *       and only the column positions recur.
 * @note Layout: four hex digits, a comma, six letters, a comma, three digits, a newline.
 */
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
            // Explicit cast narrows the mixed value to the letter it selects, inside 'a' to 'z'
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

/**
 * @brief Fills @p into with bytes from a fixed generator.
 *
 * @param[out] into   Corpus to fill [BORROWS].
 * @param[in]  length Bytes to write.
 * @note SHA-256 in counter mode, starting from block zero every run, so the numbers are reproducible.
 *       What it stands in for is a sequence with no rank ordering and no correlation between
 *       positions, which is what a normal constant's digits look like empirically.
 * @note It was a 64 bit xorshift when the skip figures of 261.1, 262.7 and 261.1 were recorded. The
 *       same rows read 271.9, 273.6 and 281.3 under this generator, so any uniform number older than
 *       this change is on the old one and cannot be compared against a new row.
 */
static void fill_uniform(uint8_t *into, size_t length)
{
    // SHA-256 in counter mode, not a small PRNG. The control corpus carries the whole weight of
    // every independence claim here, so what generates it should be the thing whose uniformity has
    // been checked against published vectors rather than a shift register nobody validated.
    // mmgr_sha256_self_test holds it to RFC 6234 and wycheproof_run.py to Wycheproof's HMAC vectors.
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
 * @brief Identifies the cost table this build linked, since it does not carry its own name.
 *
 * @return A checksum over all 256 costs.
 * @note Stamped on every row. Five builds produce five fingerprints, which is what lets rows from
 *       separate binaries be told apart after the fact.
 */
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

/**
 * @brief Counts each byte value in a corpus.
 *
 * @param[in]  corpus Bytes to count [BORROWS].
 * @param[in]  length How many.
 * @param[out] counts 256 counters [BORROWS].
 */
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

/**
 * @brief How an anchor gets picked out of a needle.
 *
 * @note The policy is a free variable, and that is the point of having it. An anchor is a condition
 *       copied out of the needle, so a position that really does hold the needle satisfies every
 *       anchor whatever chose it. Correctness cannot turn on the policy. What the policy moves is how
 *       many false candidates survive, and that is cost.
 * @note ANCHOR_BY_TABLE asks the linked cost table, which ranks a byte by how rare it is.
 *       ANCHOR_BY_RANDOM assigns costs by a permutation with no relation to how often a byte occurs.
 *       ANCHOR_BY_MAXIMUM_ENTROPY gives every byte the same cost, which is the table carrying no
 *       information at all and the floor this whole idea has to hold at.
 */
typedef enum
{
    ANCHOR_BY_TABLE = 0,
    ANCHOR_BY_RANDOM = 1,
    ANCHOR_BY_MAXIMUM_ENTROPY = 2
} AnchorPolicy;

/**
 * @brief A cost per byte value, unrelated to how often that byte occurs.
 */
static unsigned s_random_cost[256];

/**
 * @brief Fills the random cost table with a permutation of 0 through 255.
 *
 * @note Drawn from SHA-256 in counter mode for the same reason the uniform corpus is. A permutation
 *       keeps the arm honest: every cost is still distinct, so the picker behaves exactly as it does
 *       under the real table and the only thing removed is the table being right.
 */
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
                // Explicit cast narrows one byte out of the counter, most significant first
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

/**
 * @brief Returns what @p policy charges for @p byte.
 *
 * @param[in] byte   The byte value being priced.
 * @param[in] policy Which pricing rule to apply.
 * @return           A cost, where lower means the picker prefers it.
 */
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
            // One cost for every byte. Ties go leftmost, so the anchors come out at 0, 1, 2 and sit
            // adjacent, which is the hardest case there is for two rates to multiply
            return 0u;
        }
        case ANCHOR_BY_TABLE:
        default:
        {
            return (unsigned)EMBED_CALL(ancorae.impensa, AncoraeCfg, .byte = byte);
        }
    }
}

/**
 * @brief Names a policy for the row it is printed on.
 *
 * @param[in] policy Which pricing rule.
 * @return           Text naming it [BORROWS].
 */
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

/**
 * @brief Returns the offset into @p needle of the byte the cost table likes best.
 *
 * @param[in] needle First byte of the needle [BORROWS].
 * @param[in] length Bytes in it.
 * @param[in] skip   An offset to pass over, or length to pass over nothing.
 * @param[in] policy Which pricing rule decides what best means.
 * @return           The offset of the lowest cost byte, ties going to the leftmost.
 * @note Under ANCHOR_BY_TABLE lowest cost is rarest, which is the byte that admits the fewest
 *       positions and leaves the longest runs between them. Under the other two policies the word
 *       cheapest still applies and no longer means rare, which is the arm those policies exist for.
 */
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

/**
 * @brief Counts positions where one anchor, or two at their relative offsets, admit a candidate.
 *
 * @param[in]  corpus     Bytes to sift [BORROWS].
 * @param[in]  length     How many.
 * @param[in]  first      Byte the first anchor matches.
 * @param[in]  first_at   Its offset inside the needle.
 * @param[in]  second     Byte the second anchor matches.
 * @param[in]  second_at  Its offset, or SIZE_MAX for one anchor only.
 * @param[in]  needle_len Bytes in the needle, which bounds where a candidate can start.
 * @return                Positions that survive.
 */
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
        // The second anchor is one more compare on a word already in hand, which is what makes it
        // nearly free under SWAR and what the multiplication below is about
        if ((second_at != (size_t)-1) && (corpus[start + second_at] != second))
        {
            continue;
        }
        surviving++;
    }
    return surviving;
}

/**
 * @brief The most anchors a cascade row will stack.
 *
 * @note Six is where this bench stops sweeping. The count is a parameter of the shape and not a limit
 *       of it, so the ceiling is a choice about run time and the rows say what each step buys.
 */
#define CASCADE_MAX 6u

/**
 * @brief Fills @p offsets with the @p count cheapest distinct offsets in @p needle.
 *
 * @param[in]  needle     The needle to pick from [BORROWS].
 * @param[in]  needle_len Bytes in it.
 * @param[in]  policy     Which pricing rule decides what cheapest means.
 * @param[out] offsets    Receives the chosen offsets, CASCADE_MAX of them at most [BORROWS].
 * @param[in]  count      How many to pick.
 * @return                How many were picked, which is short of count only when the needle has
 *                        fewer distinct offsets than that.
 * @note One picker for every row in this file. The cost numbers and the invariant check have to be
 *       reading the same anchor set or neither says anything about the other.
 */
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

/**
 * @brief Counts positions where all @p count anchors match at their needle offsets.
 *
 * @param[in] corpus     Bytes to sift [BORROWS].
 * @param[in] length     How many.
 * @param[in] needle     The needle the anchors came from [BORROWS].
 * @param[in] offsets    Anchor offsets inside the needle [BORROWS].
 * @param[in] count      How many anchors.
 * @param[in] needle_len Bytes in the needle, which bounds where a candidate can start.
 * @return               Positions that survive every anchor.
 * @note One early exit per anchor. Under SWAR each is a mask and the whole set is an AND, so the
 *       shape here counts the same survivors a branchless form would keep.
 */
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

/**
 * @brief Reports what stacking one anchor at a time buys, from one up to CASCADE_MAX.
 *
 * @param[in] name       Text naming the corpus.
 * @param[in] corpus     Bytes to sift [BORROWS].
 * @param[in] corpus_len How many.
 * @param[in] needle_len Bytes in the needles drawn from it.
 * @param[in] policy     Which pricing rule picks the anchors.
 * @param[in] stamp      Fingerprint of the linked cost table.
 * @note Each anchor is the cheapest offset not already taken, which is the same rule the picker uses
 *       for one and for two. Nothing in the shape caps the count, and the row exists to say what each
 *       additional anchor removes once the obvious two are spent.
 */
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

            // A needle with fewer distinct offsets than the count runs the picker out. That sample is
            // dropped instead of padded with a repeat, which would count one condition twice
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

/**
 * @brief Counts true occurrences of @p needle that an anchor set refuses to admit.
 *
 * @param[in]  corpus     Bytes to sift [BORROWS].
 * @param[in]  length     How many.
 * @param[in]  needle     The needle [BORROWS].
 * @param[in]  needle_len Bytes in it.
 * @param[in]  offsets    Anchor offsets inside the needle [BORROWS].
 * @param[in]  count      How many anchors.
 * @param[out] found      Receives how many true occurrences the corpus holds [BORROWS].
 * @return                How many of those an anchor rejected.
 * @note The deductive half, run as code. An anchor is a byte lifted out of the needle at an offset
 *       inside the needle, so a position holding the whole needle holds that byte at that offset. The
 *       argument never names how many anchors there are, what picked them, how large the alphabet is,
 *       or that positions are ordered, which is why every sweep in main can vary all four and still
 *       expect zero back. A nonzero return is an implementation defect, never a property of the data.
 */
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

/**
 * @brief Sweeps anchor counts at one corpus and needle length, reporting what the anchors refused.
 *
 * @param[in] name       Text naming the corpus.
 * @param[in] corpus     Bytes to sift [BORROWS].
 * @param[in] corpus_len How many bytes it holds.
 * @param[in] needle_len Bytes in the needles drawn from it.
 * @param[in] policy     Which pricing rule picks the anchors.
 * @param[in] stamp      Fingerprint of the linked cost table.
 * @note Unlike the cost rows this one takes the degenerate lengths, because that is where a claim
 *       about all sizes either holds or does not. A needle as long as the corpus leaves one position,
 *       and a needle of one byte is the shortest thing that can carry an anchor at all.
 * @note A verdict of none means the case had nothing to check, and it is printed instead of hold so a
 *       reader cannot mistake an empty sweep for a passing one.
 */
static void report_invariant(const char *name, const uint8_t *corpus, size_t corpus_len, size_t needle_len,
                             AnchorPolicy policy, uint32_t stamp)
{
    if ((needle_len == 0u) || (needle_len > corpus_len))
    {
        return;
    }

    const size_t positions = (corpus_len - needle_len) + 1u;

    // A long needle over the flat corpus makes every position a full length compare, so the sample
    // count comes down as the needle grows. This claim needs every sample honest, not many samples
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

/**
 * @brief Reports one corpus at one needle length.
 *
 * @param[in] name          Text naming the corpus, printed in every row.
 * @param[in] corpus        Bytes to sift [BORROWS].
 * @param[in] corpus_len    How many bytes the corpus actually holds.
 * @param[in] needle_len    Bytes in the needles drawn from it.
 * @param[in] anchor_stride Distance from the first anchor to the second, or zero to let the policy
 *                          pick the second one too.
 * @param[in] policy        Which pricing rule picks the anchors.
 * @param[in] stamp         Fingerprint of the linked cost table.
 */
static void report(const char *name, const uint8_t *corpus, size_t corpus_len, size_t needle_len, size_t anchor_stride,
                   AnchorPolicy policy, uint32_t stamp)
{
    if (needle_len >= (corpus_len / 4u))
    {
        // A needle that is a quarter of the corpus leaves too few sample positions for the mean to
        // mean anything, and the sample count itself would start driving the numbers
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

        // Stride zero asks the table for the second anchor as well, which is the policy the tree
        // has now. Any other stride pins the second anchor a fixed distance away, which is what
        // tests whether the distance decorrelates the pair or the corpus defeats it
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

        // What two independent anchors would admit: the first anchor's rate times the second's,
        // over the positions the first already kept
        const double positions = (double)(corpus_len - needle_len + 1u);
        const double second_rate = (double)counts[needle[second_at]] / (double)corpus_len;

        // The needle finds itself once, by construction. That hit is not a false positive and
        // counting it as one is what made an independent corpus report a factor of fifteen
        const double two_excess = (double)two - 1.0;

        one_total += (double)one;
        two_total += two_excess;
        two_squares += two_excess * two_excess;
        // The prediction is about false positives, so it runs over the first anchor's candidates
        // with the needle's own occurrence taken out. Using the count with the self hit still in it
        // inflated every predicted value and biased the ratio low
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

    // Sample variance of the excess, then the standard error of its mean. Without it "correlated"
    // and "not correlated" are being read off point estimates with nothing to say how far apart two
    // of them have to be before the difference is real
    const double variance = (count > 1.0) ? ((two_squares - (count * two_mean * two_mean)) / (count - 1.0)) : 0.0;
    const double stderr_two = (variance > 0.0) ? (sqrt(variance) / sqrt(count)) : 0.0;

    // How many standard errors the observed excess sits above what independence predicts. Around
    // zero is independence; large is correlation the multiplication does not account for
    const double zscore = (stderr_two > 0.0) ? ((two_mean - predicted_mean) / stderr_two) : 0.0;

    printf("ancorae_sift,%08x,%s,%s,%u,%u,%u,%u,%.2f,%.2f,%.2f,%.1f,%.2f,%.3f,%.1f\n", stamp, name,
           policy_name(policy), (unsigned)needle_len, (unsigned)anchor_stride, (unsigned)corpus_len, samples,
           one_mean, two_mean, predicted_mean, skip, independence, stderr_two, zscore);
}

/**
 * @brief Reports the frequency structure of one corpus, before any needle is drawn from it.
 *
 * @param[in] name       Text naming the corpus.
 * @param[in] corpus     Bytes to measure [BORROWS].
 * @param[in] corpus_len How many.
 * @param[in] needle_len The needle length the candidate prediction is made against.
 * @param[in] stamp      Fingerprint of the linked cost table.
 * @note What an uninformed anchor costs is not a free parameter, and this row is here to say so
 *       before the sweep runs. An anchor picked with no information is a byte drawn from the corpus
 *       by the corpus's own frequencies, so it matches at the collision probability, the sum of the
 *       squared byte frequencies. Multiply that by the number of positions and the maximum entropy
 *       candidate count is predicted in advance. The sweep either lands on it or the account is wrong.
 * @note Shannon entropy sits beside it because the two answer different questions. Shannon says how
 *       many bits a byte carries on average. Collision says how often two independent draws agree,
 *       and that second one is what an anchor is actually paid in.
 */
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

    // The rate a perfectly matched table would reach, which is the ceiling on what any measure can be
    // worth. The anchor is the rarest of needle_len symbols and a needle is drawn from the corpus, so
    // each symbol arrives with probability equal to its own frequency. For draws weighted that way,
    // the expected minimum is the integral of the survival function raised to the draw count, and a
    // sorted frequency list turns that integral into a sum over its steps
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

/**
 * @brief Reports how many alignments one failed anchor refutes, beyond the position it was tested at.
 *
 * @param[in] name       Text naming the corpus.
 * @param[in] corpus     Bytes to sift [BORROWS].
 * @param[in] corpus_len How many.
 * @param[in] needle_len Bytes in the needles drawn from it.
 * @param[in] policy     Which pricing rule picks the anchor.
 * @param[in] stamp      Fingerprint of the linked cost table.
 * @note A refutation is not local, and the rest of this bench treats it as though it were. Testing the
 *       anchor at pattern offset a against corpus position s+a reads one cell. For any shift d, the
 *       alignment starting at s+d puts pattern offset a-d on that same cell, so every d whose pattern
 *       byte differs from what was read is refused by the one read. A byte the needle does not carry
 *       at all refutes every alignment touching the cell.
 * @note The count is the needle length less how many times the observed byte occurs in the needle, so
 *       its expectation over a corpus is needle_len times one minus the collision probability. That
 *       is the same collision probability the candidate count measures, appearing here as a distance
 *       instead of a rate.
 */
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

            // Alignments the one read rules out. The needle carrying that byte somewhere is what keeps
            // an alignment alive, so every offset holding a different byte is settled by this read
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

/**
 * @brief The widest symbol the width sweep reads.
 */
#define WIDEST_SYMBOL 16u

/**
 * @brief Counts for every value a symbol of the widest width can take.
 */
static uint32_t s_width_counts[1u << WIDEST_SYMBOL];

/**
 * @brief Reports the collision entropy of a corpus read at several symbol widths.
 *
 * @param[in] name       Text naming the corpus.
 * @param[in] corpus     Bytes to measure [BORROWS].
 * @param[in] corpus_len How many.
 * @param[in] stamp      Fingerprint of the linked cost table.
 * @note Every other row in this file reads the corpus eight bits at a time, which is a choice nobody
 *       here made deliberately. A corpus is a bit pattern and the byte boundary is one slice of it,
 *       so the entropy this document treats as a property of the data is really a property of the data
 *       and that slice together.
 * @note What matters to a search is not what one read yields but what one bit of reading yields, since
 *       a wider read touches more of the corpus. The last column is that ratio, and the width that
 *       maximizes it is the width worth reading at.
 * @note Windows overlap and start at every bit offset, because a read can be taken anywhere and this
 *       is measuring what a read of that width is worth, not how a stream would be segmented.
 */
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
                // Bits are taken most significant first inside each byte, which is how a byte is
                // written down and how the standard's padding indexes them
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

    // Three pricing rules, ending at the one that prices nothing. If the last arm moves the cost
    // columns and leaves the invariant column alone, that separation is the whole claim
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

    // Out to 256 so the trend in the excess has enough points to have a shape
    static const size_t lengths[] = {4u, 8u, 16u, 32u, 64u, 128u, 256u};

    // Stride zero is the table's own choice of second anchor. The rest are fixed distances, primes
    // against powers of two, which is the comparison that says whether a coprime distance breaks the
    // correlation or the corpus has structure at every distance
    static const size_t strides[] = {0u, 1u, 2u, 3u, 4u, 5u, 7u, 8u, 11u, 13u, 16u, 17u};

    // Both ends, not the comfortable middle. One byte is the shortest needle that can carry an anchor,
    // and a needle as long as the corpus leaves exactly one position to find it in
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

            // The zero entropy end belongs in the cost sweep and not only the invariant one. Every
            // position holds every needle, so no anchor can ever fail and none of them remove
            // anything. It is the case where the whole method is worth nothing, and a claim about
            // all domains has to include the domain where that is true
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
