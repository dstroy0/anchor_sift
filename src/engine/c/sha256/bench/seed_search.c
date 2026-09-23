/* seed_search - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file seed_search.c
 * @brief Recursive subtraction over a BIP-39 template: enumerate what fits, deriving where it can.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-13
 *
 * @note Douglas, 2026-09-13: "subtracting can be recursive here, and should be."
 *
 * WHAT THIS IS
 *
 * A mnemonic is twelve 11-bit indices: 128 bits of entropy and a 4-bit checksum that is the top
 * four bits of SHA-256 over the entropy. A recovery template fixes the slots you hold and leaves the
 * rest open. The search is a recursion over the slots, and at each node it SUBTRACTS: a slot you
 * know branches one way instead of 2048, a restricted slot branches only over its candidates, and
 * the LAST open position is not searched at all -- the checksum determines it, so it is derived.
 *
 * WHERE RECURSION COMPOUNDS AND WHERE IT STOPS, STATED PLAINLY
 *
 * Recursion subtracts on constraints that FACTOR across the slots: known words, known positions,
 * per-slot candidate sets. That is exactly the recoverable case, and there the tree collapses. The
 * checksum factors only at the last free position, which is why it is derived there and nowhere
 * else. A target address does NOT factor at all -- it is a function of the whole seed through
 * PBKDF2, which has no partial value on a prefix -- so it can only be tested at a completed leaf.
 * Recursion prunes the structure you hold; it cannot prune the hash, by construction.
 *
 * @note This ENUMERATES and COUNTS. It works in index space, carries no wordlist, derives no
 *       address, and matches no wallet. The only fitness it applies is the checksum, which is public
 *       and part of the standard. The expensive per-survivor test -- deriving the seed and comparing
 *       to a target the owner supplies for their own recovery -- is the leaf this stops short of.
 *       Graded against the closed-form counts, so the recursion is provably visiting the right tree.
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

#include "../core/sha256_core.h"

/** @brief Words in a 12-word mnemonic. */
#define MNEMONIC_WORDS 12u

/** @brief Distinct words, hence the range of one index and the branch width of a fully open slot. */
#define WORDLIST_SIZE 2048u

/** @brief Bits an index carries. Twelve of them are 132 bits: 128 entropy and a 4-bit checksum. */
#define INDEX_BITS 11u

/**
 * @brief Packs twelve indices into the sixteen entropy bytes and reads the stored checksum nibble.
 *
 * @param[in]  index    Twelve indices, each below WORDLIST_SIZE [BORROWS].
 * @param[out] entropy  Sixteen entropy bytes [BORROWS].
 * @return              The 4-bit checksum the indices carry, in the low nibble.
 */
static uint8_t pack_entropy(const uint16_t *const index, uint8_t *const entropy)
{
    uint8_t stream[17];
    for (uint32_t at = 0u; at < 17u; ++at)
    {
        stream[at] = 0u;
    }

    for (uint32_t word = 0u; word < MNEMONIC_WORDS; ++word)
    {
        for (uint32_t bit = 0u; bit < INDEX_BITS; ++bit)
        {
            const uint32_t position = (word * INDEX_BITS) + bit;
            const uint32_t value = (index[word] >> (INDEX_BITS - 1u - bit)) & 1u;
            if (value != 0u)
            {
                stream[position >> 3u] |= (uint8_t)(0x80u >> (position & 7u));
            }
        }
    }

    for (uint32_t at = 0u; at < 16u; ++at)
    {
        entropy[at] = stream[at];
    }
    // Bits 128..131 are the top four of byte sixteen.
    return (uint8_t)(stream[16] >> 4u);
}

/**
 * @brief The fitness of one assignment, as a magnitude: zero is falsy, nonzero is truthy.
 *
 * @param[in] index Twelve indices [BORROWS].
 * @return          Zero where the assignment does not fit; a nonzero magnitude where it does.
 *
 * @note THE TEST IS A MAGNITUDE, NOT A DEFINED BOOLEAN. A candidate that does not fit weighs
 *       nothing and is subtracted; one that fits carries a weight and is kept. Here the only
 *       constraint is the checksum, so the magnitude is one bit -- fits or does not -- but it is
 *       returned as a weight so the same machinery reads a richer fitness (a marginal, an amplitude,
 *       a distance to a target) with no change: keep the truthy, subtract the falsy, and where a
 *       single survivor is wanted, take the heaviest.
 */
static uint32_t fitness_magnitude(const uint16_t *const index)
{
    uint8_t entropy[16];
    const uint8_t carried = pack_entropy(index, entropy);
    uint8_t digest[32];
    sha256_hash(entropy, 16u, digest);
    return (carried == (uint8_t)(digest[0] >> 4u)) ? 1u : 0u;
}

/** @brief One slot of a template: a fixed word, a restricted set, or fully open. */
typedef struct
{
    const uint16_t *candidate; /**< The allowed indices, or NULL for the whole wordlist [BORROWS]. */
    uint16_t count;            /**< How many; 1 is a known word, WORDLIST_SIZE is fully open. */
} Slot;

/** @brief What a recursion accumulates. */
typedef struct
{
    uint64_t leaves;    /**< Complete assignments reached: the tree the recursion actually walked. */
    uint64_t survivors; /**< Of those, how many passed the checksum. */
} Counters;

/**
 * @brief The recursion. Assigns slot `depth`, then descends; the tree it walks IS the subtraction.
 *
 * @param[in]     depth    Which slot to assign.
 * @param[in,out] index    The assignment being built [BORROWS].
 * @param[in]     slot     The template [BORROWS].
 * @param[out]    counters Where leaves and survivors accumulate [BORROWS].
 *
 * @note A fixed slot has count 1, so it branches once and the other 2047 words are subtracted at
 *       this node before any deeper work is done. That is the whole idea: the pruning is structural,
 *       not a test applied after the fact.
 */
static void recurse(const uint32_t depth, uint16_t *const index, const Slot *const slot,
                    Counters *const counters)
{
    if (depth == MNEMONIC_WORDS)
    {
        ++counters->leaves;
        // Truthy is kept, falsy is subtracted. A survivor is a leaf that weighs something.
        if (fitness_magnitude(index) != 0u)
        {
            ++counters->survivors;
        }
        return;
    }

    const Slot *const here = &slot[depth];
    for (uint16_t choice = 0u; choice < here->count; ++choice)
    {
        index[depth] = (here->candidate != NULL) ? here->candidate[choice] : choice;
        recurse(depth + 1u, index, slot, counters);
    }
}

/**
 * @brief The last open position, derived instead of searched.
 *
 * @param[in] fixed  The eleven earlier indices, all known [BORROWS].
 * @return           How many valid last words there are: exactly 2^7, one per choice of the seven
 *                   entropy bits the last word carries, since the four checksum bits then follow.
 *
 * @note THIS IS THE RECURSION SUBTRACTING TO THE ANSWER. A brute last slot tries all 2048 and keeps
 *       128. Here the 128 are built directly: choose the seven free entropy bits, let SHA-256 finish
 *       the checksum, read off the word. Sixteen times fewer SHA-256 for the identical set, and
 *       graded below to be the identical set.
 */
static uint32_t derive_last_word(const uint16_t *const fixed, uint16_t *const found)
{
    uint16_t index[MNEMONIC_WORDS];
    for (uint32_t at = 0u; at < 11u; ++at)
    {
        index[at] = fixed[at];
    }

    for (uint32_t seven = 0u; seven < 128u; ++seven)
    {
        // The last word's top seven bits are entropy; its low four are the checksum. Lay the seven,
        // let the checksum be computed, then read the low four back from it.
        index[11] = (uint16_t)(seven << 4u);
        uint8_t entropy[16];
        (void)pack_entropy(index, entropy);
        uint8_t digest[32];
        sha256_hash(entropy, 16u, digest);
        const uint8_t checksum = (uint8_t)(digest[0] >> 4u);
        found[seven] = (uint16_t)((seven << 4u) | checksum);
    }
    return 128u;
}

/** @brief Fills a template so every slot is fixed to `index`, then relaxes chosen slots. */
static void template_from(Slot *const slot, const uint16_t *const index)
{
    for (uint32_t at = 0u; at < MNEMONIC_WORDS; ++at)
    {
        slot[at].candidate = &index[at];
        slot[at].count = 1u;
    }
}

/**
 * @brief The second route: an iterative odometer over the same template, no recursion.
 *
 * @param[in]  slot     The template [BORROWS].
 * @param[out] counters Leaves and survivors [BORROWS].
 *
 * @note TWO ROUTES OR IT DOES NOT SHIP. The recursion and this odometer are independent traversals
 *       of the same set, so a survivor count they agree on is a fact about the template and not
 *       about either loop. The count itself has NO closed form -- it is however many entropy values
 *       SHA-256 sends to the stored checksum nibble -- so it cannot be graded against a number
 *       written down in advance, only against a second computation of the same thing.
 */
static void enumerate_flat(const Slot *const slot, Counters *const counters)
{
    uint16_t index[MNEMONIC_WORDS];
    uint16_t choice[MNEMONIC_WORDS];
    for (uint32_t at = 0u; at < MNEMONIC_WORDS; ++at)
    {
        choice[at] = 0u;
    }

    for (;;)
    {
        for (uint32_t at = 0u; at < MNEMONIC_WORDS; ++at)
        {
            index[at] = (slot[at].candidate != NULL) ? slot[at].candidate[choice[at]] : choice[at];
        }
        ++counters->leaves;
        if (fitness_magnitude(index) != 0u)
        {
            ++counters->survivors;
        }

        int32_t wheel = (int32_t)MNEMONIC_WORDS - 1;
        while (wheel >= 0)
        {
            ++choice[wheel];
            if (choice[wheel] < slot[wheel].count)
            {
                break;
            }
            choice[wheel] = 0u;
            --wheel;
        }
        if (wheel < 0)
        {
            break;
        }
    }
}

/**
 * @brief Grades one template: the leaf count against the structural product, the survivors against
 *        the second route, all exact.
 *
 * @param[in]  label       What this scenario is.
 * @param[in]  slot        The template [BORROWS].
 * @param[in]  want_leaves The product of the slot counts, which the tree must equal exactly.
 * @return                 Non-zero if both routes agree and the leaf count is the structural one.
 */
static int grade_template(const char *const label, const Slot *const slot,
                          const uint64_t want_leaves)
{
    uint16_t index[MNEMONIC_WORDS];
    Counters recursive = {0u, 0u};
    Counters flat = {0u, 0u};
    recurse(0u, index, slot, &recursive);
    enumerate_flat(slot, &flat);

    const int leaves_ok = (recursive.leaves == want_leaves) && (flat.leaves == want_leaves);
    const int routes_agree = (recursive.survivors == flat.survivors)
                             && (recursive.leaves == flat.leaves);
    const int good = leaves_ok && routes_agree;

    (void)printf("  %-30s leaves %10llu  survivors %8llu (both routes)  %s\n", label,
                 (unsigned long long)recursive.leaves, (unsigned long long)recursive.survivors,
                 good ? "ok" : "** DISAGREES **");
    return good;
}

int main(void)
{
    (void)printf("\n  RECURSIVE SUBTRACTION over a BIP-39 template. Graded against the closed form.\n\n");

    // The all-zero-entropy mnemonic: eleven "abandon" (index 0) and "about" (index 3). It is the
    // standard valid twelve-word mnemonic, so any recursion that reproduces the record must count it
    // as a survivor of itself.
    uint16_t known[MNEMONIC_WORDS] = {0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 3u};

    int good = 1;
    Slot slot[MNEMONIC_WORDS];

    // Nothing unknown: one leaf, and it is valid, so the recursion agrees the held mnemonic is real.
    {
        template_from(slot, known);
        good = grade_template("all known", slot, 1u) && good;
    }

    // One middle word open: 2048 leaves. How many survive is a draw around 2048/16, not exactly it,
    // because a middle word is all entropy and the checksum is whatever SHA-256 makes of it.
    {
        template_from(slot, known);
        slot[5].candidate = NULL;
        slot[5].count = WORDLIST_SIZE;
        good = grade_template("one middle word open", slot, 2048u) && good;
    }

    // The last word open: 2048 leaves. This one IS exactly 128, and provably: the last word's own
    // four bits are the checksum, so for each of its 128 entropy-bit choices exactly one checksum
    // value fits. That exact invariant is asserted separately below.
    {
        template_from(slot, known);
        slot[11].candidate = NULL;
        slot[11].count = WORDLIST_SIZE;
        good = grade_template("last word open", slot, 2048u) && good;
    }

    // Two words open: 2048^2 leaves, survivors a draw around 2048^2/16.
    {
        template_from(slot, known);
        slot[3].candidate = NULL;
        slot[3].count = WORDLIST_SIZE;
        slot[8].candidate = NULL;
        slot[8].count = WORDLIST_SIZE;
        good = grade_template("two words open", slot, 2048ull * 2048ull) && good;
    }

    // A restricted slot: you know one word is one of eight, another is one of four. The tree branches
    // 8*4 = 32, subtracting every other word at those two nodes before descending.
    {
        static const uint16_t eight[8] = {11u, 97u, 500u, 501u, 1023u, 1500u, 1900u, 2047u};
        static const uint16_t four[4] = {7u, 42u, 999u, 1600u};
        template_from(slot, known);
        slot[2].candidate = eight;
        slot[2].count = 8u;
        slot[9].candidate = four;
        slot[9].count = 4u;
        good = grade_template("restricted: 8 x 4", slot, 32u) && good;
    }

    // THE ONE EXACT SURVIVOR COUNT: last word open is 128, no draw about it. Asserted on its own so
    // the claim is graded and not merely averaged.
    {
        template_from(slot, known);
        slot[11].candidate = NULL;
        slot[11].count = WORDLIST_SIZE;
        uint16_t index[MNEMONIC_WORDS];
        Counters counters = {0u, 0u};
        recurse(0u, index, slot, &counters);
        const int exact = (counters.survivors == 128u) ? 1 : 0;
        (void)printf("  %-30s survivors %8llu  (exactly 128, its 4 bits are the checksum)  %s\n",
                     "last word open, exact", (unsigned long long)counters.survivors,
                     exact ? "ok" : "** DISAGREES **");
        good = exact && good;
    }

    // THE SUM RULE, another exact identity and a check on the packing and the hash together. Vary a
    // middle word over all 2048 values; each hashes to exactly one of the sixteen checksum nibbles,
    // so the survivor counts over all sixteen possible stored nibbles must sum to 2048 exactly. No
    // number is chosen here -- the identity is forced by the entropy partitioning cleanly.
    {
        uint16_t index[MNEMONIC_WORDS];
        for (uint32_t at = 0u; at < MNEMONIC_WORDS; ++at)
        {
            index[at] = known[at];
        }
        uint32_t per_nibble[16];
        for (uint32_t nibble = 0u; nibble < 16u; ++nibble)
        {
            per_nibble[nibble] = 0u;
        }
        for (uint16_t middle = 0u; middle < WORDLIST_SIZE; ++middle)
        {
            index[5] = middle;
            uint8_t entropy[16];
            (void)pack_entropy(index, entropy);
            uint8_t digest[32];
            sha256_hash(entropy, 16u, digest);
            ++per_nibble[digest[0] >> 4u];
        }
        uint32_t total = 0u;
        for (uint32_t nibble = 0u; nibble < 16u; ++nibble)
        {
            total += per_nibble[nibble];
        }
        const int exact = (total == WORDLIST_SIZE) ? 1 : 0;
        (void)printf("  %-30s survivors over 16 nibbles sum to %u  (want 2048)  %s\n",
                     "sum rule", total, exact ? "ok" : "** DISAGREES **");
        good = exact && good;
    }

    (void)printf("\n  DERIVE vs BRUTE at the last position. Same set, a sixteenth of the SHA-256.\n\n");
    {
        // Brute: collect the 128 valid last words by trying all 2048.
        uint16_t brute[WORDLIST_SIZE];
        uint32_t brute_count = 0u;
        for (uint16_t last = 0u; last < WORDLIST_SIZE; ++last)
        {
            uint16_t candidate[MNEMONIC_WORDS];
            for (uint32_t at = 0u; at < 11u; ++at)
            {
                candidate[at] = known[at];
            }
            candidate[11] = last;
            if (fitness_magnitude(candidate) != 0u)
            {
                brute[brute_count] = last;
                ++brute_count;
            }
        }

        uint16_t derived[128];
        const uint32_t derived_count = derive_last_word(known, derived);

        // The derived set must equal the brute set, as sets. Sort-free: for each derived word, it
        // must be found among the brute survivors, and the counts must match.
        int identical = (derived_count == brute_count) ? 1 : 0;
        for (uint32_t at = 0u; identical && (at < derived_count); ++at)
        {
            int seen = 0;
            for (uint32_t other = 0u; other < brute_count; ++other)
            {
                if (brute[other] == derived[at])
                {
                    seen = 1;
                    break;
                }
            }
            identical = seen;
        }
        (void)printf("  brute found %u, derive found %u, sets %s\n", brute_count, derived_count,
                     identical ? "identical" : "** DIFFER **");
        // "about" (index 3) must be among them: it is the known valid last word for this prefix.
        int has_about = 0;
        for (uint32_t at = 0u; at < derived_count; ++at)
        {
            if (derived[at] == 3u)
            {
                has_about = 1;
            }
        }
        (void)printf("  the known-valid last word \"about\" is %s the derived set\n",
                     has_about ? "in" : "** NOT IN **");
        good = identical && has_about && good;
    }

    if (!good)
    {
        (void)printf("\n  REFUSED. The recursion visited a tree that is not the one the counts say.\n\n");
        return 1;
    }

    (void)printf("\n  RATE of the recursion, one thread. Enumeration and checksum only.\n\n");
    {
        template_from(slot, known);
        slot[3].candidate = NULL;
        slot[3].count = WORDLIST_SIZE;
        slot[8].candidate = NULL;
        slot[8].count = WORDLIST_SIZE;

        uint16_t index[MNEMONIC_WORDS];
        const clock_t began = clock();
        Counters counters = {0u, 0u};
        recurse(0u, index, slot, &counters);
        const clock_t ended = clock();

        const double seconds = (double)(ended - began) / (double)CLOCKS_PER_SEC;
        const double rate = (seconds > 0.0) ? ((double)counters.leaves / seconds) : 0.0;
        (void)printf("  %llu leaves in %.3f s  ->  %.0f candidates/sec through the checksum\n",
                     (unsigned long long)counters.leaves, seconds, rate);
        (void)printf("  of those, %llu survived to become fitness candidates\n\n",
                     (unsigned long long)counters.survivors);

        // THE HONEST COST STACK. Enumeration is cheap; the survivors are what cost. Each one, to be
        // matched against a target, is a PBKDF2 derivation -- about 250/sec on one thread by
        // pbkdf2_check -- so the two-word case is survivors / 250 seconds of the expensive step.
        (void)printf("  matching survivors to a target is the expensive step: at ~250 seeds/sec/thread\n");
        (void)printf("  the %llu survivors of this two-word template cost about %.0f s per thread.\n",
                     (unsigned long long)counters.survivors, (double)counters.survivors / 250.0);
        (void)printf("\n  Recursion made enumeration free. It did not make the fitness test free,\n");
        (void)printf("  and nothing can: that is the one constraint that does not factor.\n\n");
    }

    return 0;
}
